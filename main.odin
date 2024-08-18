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
FOOD_COUNT    :: 200
INITIAL_FOOD_SIZE :: 5
GROWTH_AMOUNT :: 0.1
MOVE_DURATION :: 50
SCAN_DURATION :: 60
SCAN_ANGLE    :: 180
COLLECTOR_COUNT :: 6
PREDATOR_COUNT :: 6
AVOIDANCE_DISTANCE :: 50
FOOD_PULL_SPEED :: 2
FOOD_SHRINK_RATE :: 0.05
MAX_ENERGY :: 100
ENERGY_DECAY_RATE :: 0.1
MIN_CELL_SIZE :: 5
MAX_CELL_SIZE :: 30
HAZARD_COUNT :: 3
EVOLUTION_THRESHOLD :: 50  // Amount of energy needed to evolve
MAX_CELLS :: 1000

frame_count := 0
last_cell_count := 0

cells: [dynamic]Cell

FoodTier :: enum {
    Low,
    Medium_Low,
    Medium,
    Medium_High,
    High,
}

CellType :: enum {
    Collector,
    Predator,
}

EvolutionTrait :: enum {
    None,
    FastMovement,
    LongLaser,
    EfficientEnergy,
}

FoodCell :: struct {
    position: rl.Vector2,
    active:   bool,
    being_pulled: bool,
    target_collector: ^Cell,
    size: f32,
    tier: FoodTier,
}

Cell :: struct {
    type: CellType,
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
    evolution_trait: EvolutionTrait,
}

Hazard :: struct {
    position: rl.Vector2,
    radius: f32,
}

food_tier_properties := [FoodTier]struct{color: rl.Color, energy: f32, spawn_chance: f32}{
    .Low         = {rl.WHITE, 10, 0.4},
    .Medium_Low  = {rl.GREEN, 20, 0.3},
    .Medium      = {rl.YELLOW, 30, 0.2},
    .Medium_High = {rl.ORANGE, 40, 0.08},
    .High        = {rl.PURPLE, 50, 0.02},
}

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Enhanced Collector Cells Game")
    rl.SetTargetFPS(60)

    // Initialize cells
    cells = make([dynamic]Cell, 0, COLLECTOR_COUNT + PREDATOR_COUNT)
    for i in 0..<COLLECTOR_COUNT {
        append(&cells, create_cell(.Collector))
        fmt.printf("Cells array length after spawn: %d\n", len(cells))
    }
    for i in 0..<PREDATOR_COUNT {
        append(&cells, create_cell(.Predator))
        fmt.printf("Cells array length after spawn: %d\n", len(cells))
    }

    // Initialize food cells
    food_cells := make([]FoodCell, FOOD_COUNT)
    for i in 0..<FOOD_COUNT {
        food_cells[i] = create_random_food()
    }

    // Initialize hazards
    hazards := make([]Hazard, HAZARD_COUNT)
    for i in 0..<HAZARD_COUNT {
        hazards[i] = Hazard{
            position = {f32(rand.int31_max(SCREEN_WIDTH)), f32(rand.int31_max(SCREEN_HEIGHT))},
            radius = f32(rand.int31_max(30) + 30),
        }
    }

    frame_count := 0
    last_cell_count := len(cells)

    for !rl.WindowShouldClose() {
        frame_count += 1

        // Update cells
        for i := 0; i < len(cells); i += 1 {
            update_cell(&cells[i], food_cells[:], hazards[:])
        }

        // Update food cells
        for i in 0..<FOOD_COUNT {
            update_food(&food_cells[i])
        }

        // Draw
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLUE)
        
        // Draw hazards
        for hazard in hazards {
            rl.DrawCircleV(hazard.position, hazard.radius, rl.ColorAlpha(rl.RED, 0.3))
        }
        
        // Draw cells, their lasers, and energy counters
        for cell in cells {
            position := cell.center - {cell.size/2, cell.size/2}
            color: rl.Color
            if cell.type == .Collector {
                color = rl.ColorAlpha(rl.WHITE, cell.energy / MAX_ENERGY)
            } else {
                color = rl.ColorAlpha(rl.RED, cell.energy / MAX_ENERGY)
            }
            rl.DrawRectangleV(position, {cell.size, cell.size}, color)
            if cell.is_scanning && cell.type == .Collector {
                draw_laser(cell)
            }
            
            // Draw evolution trait indicator
            trait_color : rl.Color
            #partial switch cell.evolution_trait {
                case .FastMovement: trait_color = rl.GREEN
                case .LongLaser: trait_color = rl.YELLOW
                case .EfficientEnergy: trait_color = rl.PURPLE
                case .None: trait_color = rl.WHITE
            }
            rl.DrawCircleV(cell.center + {cell.size/4, cell.size/4}, cell.size/8, trait_color)

            // Draw energy counter
            energy_text := rl.TextFormat("%d", int(cell.energy))
            text_size := 10
            text_position := position + {cell.size - f32(rl.MeasureText(energy_text, i32(text_size))), 0}
            rl.DrawText(energy_text, i32(text_position.x), i32(text_position.y), i32(text_size), rl.BLACK)
        }
        
        // Draw food cells on top
        for cell in food_cells {
            if cell.active {
                rl.DrawCircleV(cell.position, cell.size, food_tier_properties[cell.tier].color)
            }
        }
        
        // Count and display current number of collectors and predators
        collector_count, predator_count := 0, 0
        for cell in cells {
            if cell.type == .Collector do collector_count += 1
            else do predator_count += 1
        }
        debug_text := rl.TextFormat("Collectors: %d, Predators: %d, Total: %d", collector_count, predator_count, len(cells))
        rl.DrawText(debug_text, 10, 10, 20, rl.LIGHTGRAY)
        
        // Add debug information for cell count changes
        if len(cells) != last_cell_count {
            fmt.printf("Frame %d: Cell count changed from %d to %d\n", frame_count, last_cell_count, len(cells))
            last_cell_count = len(cells)
        }
        
        rl.EndDrawing()
    }

    delete(cells)
    rl.CloseWindow()
}

add_new_cell :: proc(cells: ^[dynamic]Cell, cell_type: CellType, position: rl.Vector2) {
    if len(cells) < MAX_CELLS {
        new_cell := create_cell(cell_type)
        new_cell.center = position
        append(cells, new_cell)
        fmt.printf("Cells array length after spawn: %d\n", len(cells))
    }
}

create_cell :: proc(type: CellType) -> Cell {
    return Cell{
        type = type,
        center = {f32(rand.int31_max(SCREEN_WIDTH)), f32(rand.int31_max(SCREEN_HEIGHT))},
        size = f32(SQUARE_SIZE),
        target_size = f32(SQUARE_SIZE),
        move_direction = {0, 0},
        move_timer = 0,
        is_scanning = false,
        scan_timer = 0,
        scan_angle = 0,
        energy = MAX_ENERGY,
        behavior_seed = int(rand.int31()),
        evolution_trait = .None,
    }
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
        position = {f32(rand.int31_max(SCREEN_WIDTH)), f32(rand.int31_max(SCREEN_HEIGHT))},
        active = true,
        being_pulled = false,
        target_collector = nil,
        size = INITIAL_FOOD_SIZE,
        tier = tier,
    }
}

update_cell :: proc(cell: ^Cell, food_cells: []FoodCell, hazards: []Hazard) {
    // Energy decay
    cell.energy -= ENERGY_DECAY_RATE * (cell.evolution_trait == .EfficientEnergy ? 0.5 : 1)
    if cell.energy < 0 {
        cell.energy = 0
    }

    // Check for evolution
    if cell.energy >= EVOLUTION_THRESHOLD && cell.evolution_trait == .None {
        evolve_cell(cell)
    }

    // Adjust size based on energy
    cell.target_size = MIN_CELL_SIZE + (MAX_CELL_SIZE - MIN_CELL_SIZE) * (cell.energy / MAX_ENERGY)

    if cell.energy > 0 {
        move_speed := f32(MOVE_SPEED) * (cell.evolution_trait == .FastMovement ? 1.5 : 1)

        if !cell.is_scanning || cell.type == .Predator {
            if cell.move_timer == 0 {
                // Choose new random direction
                angle := rand.float32_range(0, 2 * math.PI)
                cell.move_direction = {math.cos_f32(angle), math.sin_f32(angle)}
                cell.move_direction *= move_speed * (1 + 0.2 * math.sin_f32(f32(cell.behavior_seed)))
            }

            // Avoid other cells or chase them if predator
            for &other in cells {
                if &other != cell {
                    diff := cell.center - other.center
                    dist := rl.Vector2Length(diff)
                    if dist < AVOIDANCE_DISTANCE {
                        if cell.type == .Predator && other.type == .Collector {
                            // Chase collector
                            cell.move_direction = -diff * move_speed / dist
                        } else {
                            // Avoid
                            avoidance := diff * move_speed / dist
                            cell.move_direction += avoidance
                        }
                    }
                }
            }

            // Move towards nearest food if collector and energy is low
            if cell.type == .Collector && cell.energy < MAX_ENERGY * 0.3 {
                nearest_food := find_nearest_food(cell, food_cells)
                if nearest_food != nil {
                    direction := nearest_food.position - cell.center
                    cell.move_direction = direction * move_speed / rl.Vector2Length(direction)
                }
            }

            cell.center += cell.move_direction
            cell.move_timer += 1

            if cell.move_timer >= MOVE_DURATION + int(10 * math.sin_f32(f32(cell.behavior_seed))) {
                cell.is_scanning = cell.type == .Collector  // Only collectors scan
                cell.scan_timer = 0
                cell.scan_angle = -90
            }
        } else {
            cell.scan_timer += 1
            cell.scan_angle += f32(SCAN_ANGLE) / (f32(SCAN_DURATION) * (1 + 0.2 * math.cos_f32(f32(cell.behavior_seed))))

            if cell.type == .Collector {
                check_food_collision(cell, food_cells)
            }

            if cell.scan_timer >= SCAN_DURATION + int(10 * math.cos_f32(f32(cell.behavior_seed))) {
                cell.is_scanning = false
                cell.move_timer = 0
            }
        }

        fmt.printf("Cell energy: %f\n", cell.energy)
        // Collector reproduction
        if cell.type == .Collector && cell.energy >= 99 {
            new_cell := create_cell(.Collector)
            new_cell.center = cell.center
            new_cell.energy = 30
            new_cell.size = cell.size
            cell.energy = 70
            append(&cells, new_cell)
            fmt.printf("Cells array length after spawn: %d\n", len(cells))
            fmt.printf("---------------New collector spawned. Total cells: %d\n", len(cells))
        }
    }

    // Gradual size adjustment
    if cell.size < cell.target_size {
        cell.size += GROWTH_AMOUNT
    } else if cell.size > cell.target_size {
        cell.size -= GROWTH_AMOUNT
    }
    cell.size = clamp(cell.size, MIN_CELL_SIZE, MAX_CELL_SIZE)

    // Keep the cell within the screen bounds
    cell.center.x = clamp(cell.center.x, cell.size/2, f32(SCREEN_WIDTH) - cell.size/2)
    cell.center.y = clamp(cell.center.y, cell.size/2, f32(SCREEN_HEIGHT) - cell.size/2)

    // Check collision with hazards
    for hazard in hazards {
        if rl.CheckCollisionCircles(cell.center, cell.size/2, hazard.position, hazard.radius) {
            cell.energy -= 1  // Drain energy when in contact with hazard
            if cell.energy < 0 do cell.energy = 0
        }
    }

    // Predator eats collector and reproduces
    if cell.type == .Predator {
        for i := 0; i < len(cells); i += 1 {
            other := &cells[i]
            if other.type == .Collector && rl.CheckCollisionCircles(cell.center, cell.size/2, other.center, other.size/2) {
                cell.energy += other.energy * 0.5
                if cell.energy > MAX_ENERGY do cell.energy = MAX_ENERGY
                
                // Spawn two new predators
                new_predator1 := create_cell(.Predator)
                new_predator1.center = cell.center
                new_predator1.size = cell.size
                new_predator1.energy = 100
                
                new_predator2 := create_cell(.Predator)
                new_predator2.center = cell.center
                new_predator2.size = cell.size
                new_predator2.energy =1000
                
                cell.energy /= 3  // Divide energy among parent and two offspring
                
                append(&cells, new_predator1)
                fmt.printf("Cells array length after spawn: %d\n", len(cells))
                append(&cells, new_predator2)
                fmt.printf("Cells array length after spawn: %d\n", len(cells))
                
                // Remove the eaten collector
                ordered_remove(&cells, i)
                fmt.printf("Collector eaten. Two new predators spawned. Total cells: %d\n", len(cells))
                break // Only eat one collector per update
            }
        }
    }
}

evolve_cell :: proc(cell: ^Cell) {
    cell.evolution_trait = EvolutionTrait(rand.int31_max(len(EvolutionTrait) - 1) + 1)
    cell.energy -= EVOLUTION_THRESHOLD
}

find_nearest_food :: proc(cell: ^Cell, food_cells: []FoodCell) -> ^FoodCell {
    nearest_food: ^FoodCell = nil
    min_distance := f32(math.F32_MAX)

    for &food in food_cells {
        if food.active {
            distance := rl.Vector2Distance(cell.center, food.position)
            if distance < min_distance {
                min_distance = distance
                nearest_food = &food
            }
        }
    }

    return nearest_food
}

check_food_collision :: proc(cell: ^Cell, food_cells: []FoodCell) {
    base_direction := rl.Vector2{1, 0}
    scan_direction := rl.Vector2Rotate(base_direction, math.to_radians_f32(cell.scan_angle))
    move_angle := math.atan2_f32(cell.move_direction.y, cell.move_direction.x)
    final_direction := rl.Vector2Rotate(scan_direction, move_angle)
    laser_length := BASE_LASER_LENGTH * math.pow(cell.size / SQUARE_SIZE, 0.5) * (cell.evolution_trait == .LongLaser ? 1.5 : 1)
    laser_end := cell.center + final_direction * laser_length
    
    for i in 0..<len(food_cells) {
        if food_cells[i].active && !food_cells[i].being_pulled {
            if rl.CheckCollisionPointLine(
                food_cells[i].position,
                cell.center,
                laser_end,
                2) 
            {
                food_cells[i].being_pulled = true
                food_cells[i].target_collector = cell
                break
            }
        }
    }
}
    
update_food :: proc(food: ^FoodCell) {
    if food.being_pulled && food.target_collector != nil {
        direction := food.target_collector.center - food.position
        direction = rl.Vector2Normalize(direction)
        food.position += direction * FOOD_PULL_SPEED

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

draw_laser :: proc(cell: Cell) {
    base_direction := rl.Vector2{1, 0}
    scan_direction := rl.Vector2Rotate(base_direction, math.to_radians_f32(cell.scan_angle))
    move_angle := math.atan2_f32(cell.move_direction.y, cell.move_direction.x)
    final_direction := rl.Vector2Rotate(scan_direction, move_angle)
    laser_length := BASE_LASER_LENGTH * math.pow(cell.size / SQUARE_SIZE, 0.5) * (cell.evolution_trait == .LongLaser ? 1.5 : 1)
    laser_end := cell.center + final_direction * laser_length
    laser_color := rl.ColorAlpha(rl.SKYBLUE, cell.energy / MAX_ENERGY)
    rl.DrawLineEx(
        cell.center,
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