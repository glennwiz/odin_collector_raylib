package main

import "core:fmt"
import "core:math/rand"
import "core:math"
import rl "vendor:raylib"

SCREEN_WIDTH  :: 800
SCREEN_HEIGHT :: 450
SQUARE_SIZE   :: 5
MOVE_SPEED    :: 2
BASE_LASER_LENGTH :: 50
FOOD_COUNT    :: 20
INITIAL_FOOD_SIZE :: 5
GROWTH_AMOUNT :: 0.1
MOVE_DURATION :: 50
SCAN_DURATION :: 60
SCAN_ANGLE    :: 180
COLLECTOR_COUNT :: 4
AVOIDANCE_DISTANCE :: 50
FOOD_PULL_SPEED :: 2
FOOD_SHRINK_RATE :: 0.05
MAX_ENERGY :: 100
ENERGY_DECAY_RATE :: 0.1
MIN_CELL_SIZE :: 5
MAX_CELL_SIZE :: 30

FoodTier :: enum {
    Low,
    Medium_Low,
    Medium,
    Medium_High,
    High,
}

FoodCell :: struct {
    position: rl.Vector2,
    active:   bool,
    being_pulled: bool,
    target_collector: ^CollectorCell,
    size: f32,
    tier: FoodTier,
}

CollectorCell :: struct {
    center: rl.Vector2,
    size: f32,
    target_size: f32,
    move_direction: rl.Vector2,
    move_timer: int,
    is_scanning: bool,
    scan_timer: int,
    scan_angle: f32,
    energy: f32,
    behavior_seed: int,
}

food_tier_properties := [FoodTier]struct{color: rl.Color, energy: f32, spawn_chance: f32}{
    .Low         = {rl.WHITE, 10, 0.4},
    .Medium_Low  = {rl.GREEN, 20, 0.3},
    .Medium      = {rl.YELLOW, 30, 0.2},
    .Medium_High = {rl.ORANGE, 40, 0.08},
    .High        = {rl.PURPLE, 50, 0.02},
}

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Collector Cells Game")
    rl.SetTargetFPS(60)

    // Initialize food cells
    food_cells := make([]FoodCell, FOOD_COUNT)
    for i in 0..<FOOD_COUNT {
        food_cells[i] = create_random_food()
    }

    // Initialize collector cells
    collector_cells := make([]CollectorCell, COLLECTOR_COUNT)
    for i in 0..<COLLECTOR_COUNT {
        collector_cells[i] = CollectorCell{
            center = {f32(rand.int_max(SCREEN_WIDTH)), f32(rand.int_max(SCREEN_HEIGHT))},
            size = f32(SQUARE_SIZE),
            target_size = f32(SQUARE_SIZE),
            move_direction = {0, 0},
            move_timer = 0,
            is_scanning = false,
            scan_timer = 0,
            scan_angle = 0,
            energy = MAX_ENERGY,
            behavior_seed = rand.int_max(1000),
        }
    }

    for !rl.WindowShouldClose() {
        // Update collector cells
        for i in 0..<COLLECTOR_COUNT {
            update_collector(&collector_cells[i], collector_cells[:], food_cells[:])
        }

        // Update food cells
        for i in 0..<FOOD_COUNT {
            update_food(&food_cells[i])
        }

        // Draw
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLUE)
        
        // Draw collector cells and their lasers
        for collector in collector_cells {
            position := rl.Vector2{collector.center.x - collector.size/2, collector.center.y - collector.size/2}
            color := rl.ColorAlpha(rl.WHITE, collector.energy / MAX_ENERGY)
            rl.DrawRectangleV(position, {collector.size, collector.size}, color)
            if collector.is_scanning {
                draw_laser(collector)
            }
        }
        
        // Draw food cells on top
        for cell in food_cells {
            if cell.active {
                rl.DrawCircleV(cell.position, cell.size, food_tier_properties[cell.tier].color)
            }
        }
        
        rl.DrawText("Collector Cells!", 190, 0, 20, rl.LIGHTGRAY)
        
        rl.EndDrawing()
    }

    rl.CloseWindow()
}

create_random_food :: proc() -> FoodCell {
    roll := rand.float32_range(0, 1)
    tier: FoodTier
    cumulative_chance: f32 = 0
    for t in FoodTier {
        cumulative_chance += food_tier_properties[t].spawn_chance
        if roll <= cumulative_chance {
            tier = t
            break
        }
    }

    return FoodCell{
        position = {f32(rand.int_max(SCREEN_WIDTH)), f32(rand.int_max(SCREEN_HEIGHT))},
        active = true,
        being_pulled = false,
        target_collector = nil,
        size = INITIAL_FOOD_SIZE,
        tier = tier,
    }
}

update_collector :: proc(collector: ^CollectorCell, all_collectors: []CollectorCell, food_cells: []FoodCell) {
    // Energy decay
    collector.energy -= ENERGY_DECAY_RATE
    if collector.energy < 0 {
        collector.energy = 0
    }

    // Adjust size based on energy
    collector.target_size = MIN_CELL_SIZE + (MAX_CELL_SIZE - MIN_CELL_SIZE) * (collector.energy / MAX_ENERGY)

    if collector.energy > 0 {
        if !collector.is_scanning {
            if collector.move_timer == 0 {
                // Choose new random direction
                angle := rand.float32_range(0, 2 * math.PI)
                collector.move_direction = {math.cos_f32(angle), math.sin_f32(angle)}
                collector.move_direction *= MOVE_SPEED * (1 + 0.2 * math.sin_f32(f32(collector.behavior_seed)))
            }

            // Avoid other collectors
            for &other in all_collectors {
                if &other != collector {
                    diff := collector.center - other.center
                    dist := rl.Vector2Length(diff)
                    if dist < AVOIDANCE_DISTANCE {
                        avoidance := rl.Vector2Normalize(diff) * MOVE_SPEED
                        collector.move_direction += avoidance
                    }
                }
            }

            // Move towards nearest food if energy is low
            if collector.energy < MAX_ENERGY * 0.3 {
                nearest_food := find_nearest_food(collector, food_cells)
                if nearest_food != nil {
                    direction := rl.Vector2Subtract(nearest_food.position, collector.center)
                    collector.move_direction = rl.Vector2Scale(rl.Vector2Normalize(direction), MOVE_SPEED)
                }
            }

            collector.center += collector.move_direction
            collector.move_timer += 1

            if collector.move_timer >= MOVE_DURATION + int(10 * math.sin_f32(f32(collector.behavior_seed))) {
                collector.is_scanning = true
                collector.scan_timer = 0
                collector.scan_angle = -90
            }
        } else {
            collector.scan_timer += 1
            collector.scan_angle += f32(SCAN_ANGLE) / (f32(SCAN_DURATION) * (1 + 0.2 * math.cos_f32(f32(collector.behavior_seed))))

            check_food_collision(collector, food_cells)

            if collector.scan_timer >= SCAN_DURATION + int(10 * math.cos_f32(f32(collector.behavior_seed))) {
                collector.is_scanning = false
                collector.move_timer = 0
            }
        }
    }

    // Gradual size adjustment
    if collector.size < collector.target_size {
        collector.size += GROWTH_AMOUNT
    } else if collector.size > collector.target_size {
        collector.size -= GROWTH_AMOUNT
    }
    collector.size = clamp(collector.size, MIN_CELL_SIZE, MAX_CELL_SIZE)

    // Keep the collector within the screen bounds
    collector.center.x = clamp(collector.center.x, collector.size/2, f32(SCREEN_WIDTH) - collector.size/2)
    collector.center.y = clamp(collector.center.y, collector.size/2, f32(SCREEN_HEIGHT) - collector.size/2)
}

find_nearest_food :: proc(collector: ^CollectorCell, food_cells: []FoodCell) -> ^FoodCell {
    nearest_food: ^FoodCell = nil
    min_distance := f32(math.F32_MAX)

    for &food in food_cells {
        if food.active {
            distance := rl.Vector2Distance(collector.center, food.position)
            if distance < min_distance {
                min_distance = distance
                nearest_food = &food
            }
        }
    }

    return nearest_food
}

check_food_collision :: proc(collector: ^CollectorCell, food_cells: []FoodCell) {
    base_direction := rl.Vector2{1, 0}
    scan_direction := rl.Vector2Rotate(base_direction, math.to_radians_f32(collector.scan_angle))
    move_angle := math.atan2_f32(collector.move_direction.y, collector.move_direction.x)
    final_direction := rl.Vector2Rotate(scan_direction, move_angle)
    laser_length := BASE_LASER_LENGTH * math.pow(collector.size / SQUARE_SIZE, 0.5)
    laser_end := rl.Vector2Add(collector.center, rl.Vector2Scale(final_direction, laser_length))
    
    for i in 0..<len(food_cells) {
        if food_cells[i].active && !food_cells[i].being_pulled {
            if rl.CheckCollisionPointLine(
                food_cells[i].position,
                collector.center,
                laser_end,
                2
            ) {
                food_cells[i].being_pulled = true
                food_cells[i].target_collector = collector
                break
            }
        }
    }
}

update_food :: proc(food: ^FoodCell) {
    if food.being_pulled && food.target_collector != nil {
        direction := rl.Vector2Subtract(food.target_collector.center, food.position)
        direction = rl.Vector2Normalize(direction)
        food.position = rl.Vector2Add(food.position, rl.Vector2Scale(direction, FOOD_PULL_SPEED))

        // Shrink the food as it's being pulled
        food.size -= FOOD_SHRINK_RATE
        if food.size < 0.5 {
            food.size = 0.5  // Minimum size to keep it visible
        }

        if rl.CheckCollisionCircleRec(
            food.position,
            food.size,
            {food.target_collector.center.x - food.target_collector.size/2,
             food.target_collector.center.y - food.target_collector.size/2,
             food.target_collector.size,
             food.target_collector.size}
        ) {
            food.target_collector.energy += food_tier_properties[food.tier].energy
            if food.target_collector.energy > MAX_ENERGY {
                food.target_collector.energy = MAX_ENERGY
            }
            reset_food(food)
        }
    }
}

reset_food :: proc(food: ^FoodCell) {
    new_food := create_random_food()
    food^ = new_food
}

draw_laser :: proc(collector: CollectorCell) {
    base_direction := rl.Vector2{1, 0}
    scan_direction := rl.Vector2Rotate(base_direction, math.to_radians_f32(collector.scan_angle))
    move_angle := math.atan2_f32(collector.move_direction.y, collector.move_direction.x)
    final_direction := rl.Vector2Rotate(scan_direction, move_angle)
    laser_length := BASE_LASER_LENGTH * math.pow(collector.size / SQUARE_SIZE, 0.5)
    laser_end := rl.Vector2Add(collector.center, rl.Vector2Scale(final_direction, laser_length))
    laser_color := rl.ColorAlpha(rl.SKYBLUE, collector.energy / MAX_ENERGY)
    rl.DrawLineEx(
        collector.center,
        laser_end,
        2,
        laser_color,
    )
}

// Helper function to clamp a value between a minimum and maximum
clamp :: proc(value, min, max: f32) -> f32 {
    if value < min do return min
    if value > max do return max
    return value
}