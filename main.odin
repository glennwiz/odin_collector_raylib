package main

import "core:fmt"
import "core:math/rand"
import "core:math/linalg"
import "core:math"
import "core:time"
import rl "vendor:raylib"

// Constants
COLLECTOR_COUNT :: 8
PREDATOR_COUNT :: 8

FPS :: 60
SCREEN_WIDTH  :: 800
SCREEN_HEIGHT :: 450
SQUARE_SIZE   :: 5
MOVE_SPEED    :: 1
BASE_LASER_LENGTH :: 50
FOOD_COUNT    :: 30
INITIAL_FOOD_SIZE :: 5
GROWTH_AMOUNT :: 0.15
MOVE_DURATION :: 40
PREDATOR_ENERGY_DECAY_RATE :: 0.02 
AVOIDANCE_DISTANCE :: 50
FOOD_PULL_SPEED :: 2
FOOD_SHRINK_RATE :: 0.05
MAX_ENERGY :: 100
ENERGY_DECAY_RATE :: 0.1
MIN_CELL_SIZE :: 5
MAX_CELL_SIZE :: 30
HAZARD_COUNT :: 3
EVOLUTION_THRESHOLD :: 50
MAX_CELLS :: 1000
GOLDEN_FOOD_SPAWN_INTERVAL :: 100
INITIAL_PREDATOR_ENERGY :: 80
PING_INTERVAL :: 2.0  // seconds
PING_SPEED :: 3.0
MAX_PING_RADIUS :: 100.0
PING_COOLDOWN :: 0.1  // seconds

// reproduction constants
PREDATOR_REPRODUCTION_THRESHOLD :: 90.0
PARENT_ENERGY_AFTER_REPRODUCTION :: 50.0
OFFSPRING_INITIAL_ENERGY :: 30.0

// drain constants
PREDATOR_DRAIN_TIMER :: 3  // seconds
DRAIN_THICKNES :: 1
DRAIN_DOT_SIZE :: 2
RAINBOW_SPEED :: 0.05
DRAIN_BALL_COUNT :: 5
RAINBOW_CYCLE_SPEED :: 0.02

// scan constants
SCAN_DURATION :: 60
SCAN_ANGLE    :: 180

// Pulse constants
PULSE_COOLDOWN :: 5.0  // seconds
PULSE_DURATION :: 0.5  // seconds
PULSE_SPEED :: 100.0   // units per second
MAX_PULSE_RADIUS :: 30.0
PULSE_FORCE :: 10.0
SHIELD_PULSE_SPEED :: 1.0 

// Hook constants
HOOK_SPEED :: 2.0
HOOK_MAX_LENGTH :: 50.0
HOOK_COOLDOWN :: 60 // frames
ENERGY_DRAIN_RATE :: 5.0 // Amount of energy drained per frame

DEBUG_MODE :: #config(DEBUG, false) // run with  -  -  odin run . -define:DEBUG=true
DEBUG_FPS :: 10

// Enums and Structs
FoodTier :: enum {
    Low,
    Medium_Low,
    Medium,
    Medium_High,
    High,    
    Golden,
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
    is_golden: bool,
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
    is_hooking: bool,
    hook_target: ^Cell,
    hook_position: rl.Vector2,
    hook_length: f32,
    hook_max_length: f32,
    is_pinging: bool,
    ping_radius: f32,
    ping_cooldown: f32,
    can_pulse: bool,
    pulse_cooldown: f32,
    is_pulsing: bool,
    pulse_radius: f32,
    is_draining: bool,
    drain_timer: int,
    draining_predator: ^Cell,
}

Hazard :: struct {
    position: rl.Vector2,
    radius: f32,
}

// Global variables
cells: [dynamic]Cell
food_cells: [dynamic]FoodCell
hazards: [HAZARD_COUNT]Hazard
frame_count: int
last_cell_count: int
debug_info: [dynamic]string

food_tier_properties := [FoodTier]struct{color: rl.Color, energy: f32, spawn_chance: f32}{
    .Low         = {rl.WHITE, 10, 0.4},
    .Medium_Low  = {rl.GREEN, 20, 0.3},
    .Medium      = {rl.YELLOW, 30, 0.2},
    .Medium_High = {rl.ORANGE, 40, 0.08},
    .High        = {rl.PURPLE, 50, 0.02},
    .Golden      = {rl.GOLD, 200, 0.005},
}

rainbow_colors := [DRAIN_BALL_COUNT]rl.Color{
    rl.BLUE,
    rl.GREEN,
    rl.YELLOW,
    rl.ORANGE,
    rl.RED,
}

main :: proc() {
    initialize_game()
    defer cleanup()

    for !rl.WindowShouldClose() {
        if DEBUG_MODE {
            time.sleep(time.Second / DEBUG_FPS)
        }
        update_game()
        draw_game()
        if DEBUG_MODE {
            process_debug_info()
        }
    }
}

process_debug_info :: proc() {
    for info in debug_info {
        fmt.println(info)
    }
    clear(&debug_info)
}

initialize_game :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Enhanced Collector Cells Game")
    rl.SetTargetFPS(60)

    cells = make([dynamic]Cell, 0, COLLECTOR_COUNT + PREDATOR_COUNT)
    food_cells = make([dynamic]FoodCell, FOOD_COUNT)
    initialize_cells()
    initialize_food_cells()
    initialize_hazards()

    frame_count = 0
    last_cell_count = len(cells)
}

initialize_cells :: proc() {
    for i in 0..<COLLECTOR_COUNT {
        append(&cells, create_cell(.Collector))
    }
    for i in 0..<PREDATOR_COUNT {
        append(&cells, create_cell(.Predator))
    }
}

initialize_food_cells :: proc() {
    for i in 0..<FOOD_COUNT {
        append(&food_cells, create_random_food())
    }
}

initialize_hazards :: proc() {
    for i in 0..<HAZARD_COUNT {
        hazards[i] = Hazard{
            position = {f32(rand.int31_max(SCREEN_WIDTH)), f32(rand.int31_max(SCREEN_HEIGHT))},
            radius = f32(rand.int31_max(30) + 30),
        }
    }
}

get_rainbow_color :: proc(t: f32) -> rl.Color {
    r := math.sin_f32(t) * 0.5 + 0.5
    g := math.sin_f32(t + 2.0944) * 0.5 + 0.5 // 2.0944 radians = 120 degrees
    b := math.sin_f32(t + 4.1888) * 0.5 + 0.5 // 4.1888 radians = 240 degrees
    return rl.ColorAlpha({u8(r * 255), u8(g * 255), u8(b * 255), 255}, 0.8)
}

update_game :: proc() {
    frame_count += 1

    for i := 0; i < len(cells); {
        if cells[i].energy <= 0 {
            ordered_remove(&cells, i)
        } else {
            update_cell(&cells[i])
            i += 1
        }
    }

    adjust_overlapping_cells()

    // Update all food cells, including any extra golden food
    for i := 0; i < len(food_cells); i += 1 {
        update_food(&food_cells[i])
    }

    if frame_count % GOLDEN_FOOD_SPAWN_INTERVAL == 0 {
        spawn_golden_food()
    }

    // Remove any extra non-golden inactive food
    for i := FOOD_COUNT; i < len(food_cells); {
        if !food_cells[i].active && !food_cells[i].is_golden {
            ordered_remove(&food_cells, i)
        } else {
            i += 1
        }
    }

    check_cell_count_change()

    if DEBUG_MODE {
        collect_debug_info()
    }
}

collect_debug_info :: proc() {
    append(&debug_info, fmt.tprintf("Frame: %d", frame_count))
    append(&debug_info, fmt.tprintf("Total Cells: %d", len(cells)))
    append(&debug_info, fmt.tprintf("Total Food: %d", FOOD_COUNT))
    
    collector_count, predator_count := count_cell_types()
    append(&debug_info, fmt.tprintf("Collectors: %d, Predators: %d", collector_count, predator_count))
}

draw_game :: proc() {
    rl.BeginDrawing()
    defer rl.EndDrawing()

    rl.ClearBackground(rl.BLUE)
    
    draw_hazards()
    draw_cells()
    draw_food()
    draw_debug_info()

    if DEBUG_MODE {
        draw_debug_overlay()
    }
}

draw_hazards :: proc() {
    for hazard in hazards {
        rl.DrawCircleV(hazard.position, hazard.radius, rl.ColorAlpha(rl.RED, 0.3))
    }
}

draw_cell :: proc(cell: Cell) {
    position := cell.center - {cell.size/2, cell.size/2}
    color: rl.Color
    if cell.type == .Collector {
        color = rl.ColorAlpha(rl.WHITE, cell.energy / MAX_ENERGY)
    } else {
        color = rl.ColorAlpha(rl.RED, cell.energy / MAX_ENERGY)
    }
    
    rl.DrawRectangleV(position, {cell.size, cell.size}, color)
    
    if cell.is_scanning && cell.type == .Collector {
        draw_laser(cell, cell.center)
    }
    
    draw_evolution_trait(cell, cell.center)
    draw_energy_counter(cell, cell.center)

    if cell.type == .Predator {
        if cell.is_hooking {
            rl.DrawLineEx(cell.center, cell.hook_position, 2, rl.RED)
            rl.DrawCircleV(cell.hook_position, 5, rl.RED)
        }        
        
        if cell.is_pinging {
            ping_color := rl.ColorAlpha(rl.RED, 0.5 - (cell.ping_radius / MAX_PING_RADIUS) * 0.5)
            rl.DrawCircleLines(i32(cell.center.x), i32(cell.center.y), f32(cell.ping_radius), ping_color)
            
            // Add a small circle at the center for better visibility
            rl.DrawCircleV(cell.center, 3, rl.RED)
            
            // Add radial lines for a more dynamic look
            num_lines := 8
            for i in 0..<num_lines {
                angle := f32(i) * (2 * math.PI / f32(num_lines))
                end_x := cell.center.x + math.cos_f32(angle) * cell.ping_radius
                end_y := cell.center.y + math.sin_f32(angle) * cell.ping_radius
                rl.DrawLineEx(cell.center, {end_x, end_y}, 1, ping_color)
            }
        }
    }

    // Draw drain effect
    if cell.type == .Collector && cell.is_draining && cell.draining_predator != nil {
        // Draw pulsating white line
        pulse_factor := 0.5 + 0.5 * math.sin_f32(f32(frame_count) * 0.2)
        line_color := rl.ColorAlpha(rl.WHITE, pulse_factor)
        rl.DrawLineEx(cell.center, cell.draining_predator.center, DRAIN_THICKNES, line_color)
       
        // Draw energy particles
        direction := rl.Vector2Normalize(cell.center - cell.draining_predator.center)
        for i in 0..<DRAIN_BALL_COUNT {
            t := f32(frame_count % FPS) / f32(FPS)
            particle_pos := linalg.lerp(cell.draining_predator.center, cell.center, t + f32(i) * 0.2)
            
            // Calculate the color index, cycling through the rainbow colors
            color_index := (i + int(f32(frame_count) * RAINBOW_CYCLE_SPEED)) % DRAIN_BALL_COUNT
            particle_color := rainbow_colors[color_index]
            
            rl.DrawCircleV(particle_pos, DRAIN_DOT_SIZE, particle_color)
        }
    }

    // Purple pulsing shield visualization for collectors
    if cell.type == .Collector {
        shield_radius := cell.size * 0.75
        pulse_factor := 0.2 * (1 + math.sin_f32(f32(frame_count) * SHIELD_PULSE_SPEED))
        
        if cell.is_pulsing {
            // Expand the shield when pulsing
            shield_radius = linalg.lerp(shield_radius, MAX_PULSE_RADIUS, cell.pulse_radius / MAX_PULSE_RADIUS)
            pulse_factor *= 2  // Increase the pulse intensity when active
        }
        
        shield_color := rl.ColorAlpha(rl.PURPLE, 0.3 + pulse_factor)
        rl.DrawCircleV(cell.center, shield_radius, shield_color)
        
        // Draw shield border
        border_color := rl.ColorAlpha(rl.PURPLE, 0.7 + pulse_factor)
        rl.DrawCircleLines(i32(cell.center.x), i32(cell.center.y), shield_radius, border_color)
        
        // Add some "energy sparks" around the shield
        if cell.is_pulsing {
            for i := 0; i < 8; i += 1 {
                angle := f32(i) * (2 * math.PI / 8) + f32(frame_count) * 0.1
                spark_distance := shield_radius * (0.9 + 0.2 * math.sin_f32(angle * 3))
                spark_pos := rl.Vector2{
                    cell.center.x + math.cos_f32(angle) * spark_distance,
                    cell.center.y + math.sin_f32(angle) * spark_distance,
                }
                rl.DrawCircleV(spark_pos, 2, rl.PURPLE)
            }
        }
    }
}

draw_cells :: proc() {
    for cell in cells {
        draw_cell(cell)
    }
}

draw_debug_overlay :: proc() {
    debug_text_size :: 15
    line_spacing :: 5
    start_y := 40 

    for info, i in debug_info {
        y_pos := start_y + i * (debug_text_size + line_spacing)
        rl.DrawText(cstring(raw_data(info)), 10, i32(y_pos), debug_text_size, rl.WHITE)
    }
}


draw_evolution_trait :: proc(cell: Cell, center: rl.Vector2) {
    trait_color := get_trait_color(cell.evolution_trait)
    rl.DrawCircleV(center + {cell.size/4, cell.size/4}, cell.size/8, trait_color)
}

get_trait_color :: proc(trait: EvolutionTrait) -> rl.Color {
    #partial switch trait {
        case .FastMovement: return rl.GREEN
        case .LongLaser: return rl.YELLOW
        case .EfficientEnergy: return rl.PURPLE
        case: return rl.WHITE
    }
}

draw_energy_counter :: proc(cell: Cell, center: rl.Vector2) {
    energy_text := rl.TextFormat("%d", int(cell.energy))
    text_size := 10
    position := center - {cell.size/2, cell.size/2}
    text_position := position + {cell.size - f32(rl.MeasureText(energy_text, i32(text_size))), 0}
    rl.DrawText(energy_text, i32(text_position.x), i32(text_position.y), i32(text_size), rl.BLACK)
}

draw_food :: proc() {
    for food in food_cells {
        if food.active {
            rl.DrawCircleV(food.position, food.size, food_tier_properties[food.tier].color)
            if food.tier == .Golden {
                draw_star(food.position, food.size * 1.5, rl.GOLD)
            }
        }
    }
}

spawn_golden_food :: proc() {
    // First, try to replace an existing inactive food
    for &food in food_cells {
        if !food.active {
            food = create_random_food()
            food.tier = .Golden
            food.size = INITIAL_FOOD_SIZE * 1.5
            food.is_golden = true
            return
        }
    }
    
    // If all food cells are active, create a new one
    new_golden_food := FoodCell{
        position = {f32(rand.int31_max(SCREEN_WIDTH)), f32(rand.int31_max(SCREEN_HEIGHT))},
        active = true,
        being_pulled = false,
        target_collector = nil,
        size = INITIAL_FOOD_SIZE * 1.5,
        tier = .Golden,
        is_golden = true,
    }
    append(&food_cells, new_golden_food)
}

draw_debug_info :: proc() {
    collector_count, predator_count := count_cell_types()
    debug_text := rl.TextFormat("Collectors: %d, Predators: %d, Total: %d", collector_count, predator_count, len(cells))
    rl.DrawText(debug_text, 10, 10, 20, rl.LIGHTGRAY)
}

draw_star :: proc(center: rl.Vector2, size: f32, color: rl.Color) {
    points := 5
    outer_radius := size
    inner_radius := size * 0.5
    rotation := f32(frame_count) * 0.05  // Rotate the star slowly

    for i in 0..<points*2 {
        angle := rotation + f32(i) * math.PI / f32(points)
        radius := outer_radius if i % 2 == 0 else inner_radius
        x := center.x + math.cos_f32(angle) * radius
        y := center.y + math.sin_f32(angle) * radius
        next_angle := rotation + f32(i+1) * math.PI / f32(points)
        next_radius := inner_radius if i % 2 == 0 else outer_radius
        next_x := center.x + math.cos_f32(next_angle) * next_radius
        next_y := center.y + math.sin_f32(next_angle) * next_radius
        rl.DrawLineEx({x, y}, {next_x, next_y}, 2, color)
    }
}

count_cell_types :: proc() -> (int, int) {
    collector_count, predator_count := 0, 0
    for cell in cells {
        if cell.type == .Collector do collector_count += 1
        else do predator_count += 1
    }
    return collector_count, predator_count
}

check_cell_count_change :: proc() {
    if len(cells) != last_cell_count {
        fmt.printf("Frame %d: Cell count changed from %d to %d\n", frame_count, last_cell_count, len(cells))
        last_cell_count = len(cells)
    }
}

create_cell :: proc(type: CellType) -> Cell {
    energy := type == .Predator ? INITIAL_PREDATOR_ENERGY : MAX_ENERGY
    
    // Add some randomness to the initial position
    initial_position := rl.Vector2{
        f32(rand.int31_max(SCREEN_WIDTH)),
        f32(rand.int31_max(SCREEN_HEIGHT)),
    }
    
    return Cell{
        type = type,
        center = initial_position,
        size = f32(SQUARE_SIZE),
        target_size = SQUARE_SIZE,
        move_direction = {0, 0},
        move_timer = 0,
        is_scanning = false,
        scan_timer = 0,
        scan_angle = 0,
        energy = f32(energy),
        behavior_seed = int(rand.int31()),
        evolution_trait = .None,
        is_hooking = false,
        hook_target = nil,
        hook_position = {0, 0},
        hook_length = 0,
        hook_max_length = HOOK_MAX_LENGTH,
        is_pinging = false,
        ping_radius = 0,
        ping_cooldown = 0,
        can_pulse = type == .Collector,
        pulse_cooldown = 0,
        is_pulsing = false,
        pulse_radius = 0,
        is_draining = false,
        drain_timer = 0,
        draining_predator = nil,
    }
}

adjust_overlapping_cells :: proc() {
    for i := 0; i < len(cells); i += 1 {
        for j := i + 1; j < len(cells); j += 1 {
            cell1 := &cells[i]
            cell2 := &cells[j]
            
            diff := cell1.center - cell2.center
            distance := rl.Vector2Length(diff)
            
            if distance < cell1.size / 2 + cell2.size / 2 {
                // Cells are overlapping, move them apart
                overlap := (cell1.size / 2 + cell2.size / 2 - distance) / 2
                movement := rl.Vector2Normalize(diff) * overlap
                
                cell1.center = wrap_position(cell1.center + movement)
                cell2.center = wrap_position(cell2.center - movement)
            }
        }
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
        is_golden = false, 
    }
}

update_cell :: proc(cell: ^Cell) {
    // Energy decay
    decay_rate := ENERGY_DECAY_RATE
    if cell.type == .Predator {
        decay_rate = PREDATOR_ENERGY_DECAY_RATE
    }
    
    if cell.evolution_trait == .EfficientEnergy {
        decay_rate *= 0.5
    }
    
    cell.energy -= f32(decay_rate)
    if cell.energy < 0 {
        cell.energy = 0
        return  // Cell will be removed in the update_game procedure
    }

    // Check for evolution
    if cell.energy >= EVOLUTION_THRESHOLD && cell.evolution_trait == .None {
        evolve_cell(cell)
    }


    if cell.type == .Predator {
        update_predator_ping(cell, 1.0 / 60.0)
        update_hook(cell)
        
        if cell.energy >= PREDATOR_REPRODUCTION_THRESHOLD {
            new_predator := create_cell(.Predator)
            
            // Add a random offset to the new predator's position
            offset := rl.Vector2{
                rand.float32_range(-cell.size, cell.size),
                rand.float32_range(-cell.size, cell.size),
            }
            new_predator.center = wrap_position(cell.center + offset)
            
            new_predator.size = cell.size
            
            // Set fixed energy values for parent and offspring
            cell.energy = PARENT_ENERGY_AFTER_REPRODUCTION
            new_predator.energy = OFFSPRING_INITIAL_ENERGY
            
            append(&cells, new_predator)
            fmt.printf("DEBUG: New predator spawned. Parent energy: %.2f, Offspring energy: %.2f\n", 
                       cell.energy, new_predator.energy)
            fmt.printf("New predator spawned. Total cells: %d\n", len(cells))
        }        

        fmt.printf("DEBUG: Predator energy: %.2f\n", cell.energy)
    }


    // Adjust size based on energy
    cell.target_size = MIN_CELL_SIZE + (MAX_CELL_SIZE - MIN_CELL_SIZE) * (cell.energy / MAX_ENERGY)

    if cell.energy > 0 {
        move_speed := f32(MOVE_SPEED) * (cell.evolution_trait == .FastMovement ? 1.5 : 1)

        if !cell.is_scanning || cell.type == .Predator {
            update_cell_movement(cell, move_speed)
        } else {
            update_cell_scanning(cell)
        }

        handle_cell_reproduction(cell)
    }

    if cell.is_draining {
        if cell.drain_timer > 0 {
            cell.drain_timer -= 1
            if cell.drain_timer % FPS == 0 && cell.draining_predator != nil {  // Every second
                energy_drain := min(1, cell.draining_predator.energy)
                cell.draining_predator.energy -= energy_drain
                cell.energy += energy_drain
                
                // Clamp energies
                cell.draining_predator.energy = max(0, cell.draining_predator.energy)
                cell.energy = min(MAX_ENERGY, cell.energy)
            }
        } else {
            cell.is_draining = false
            cell.draining_predator = nil
        }
    }

    if cell.type == .Collector {
        update_collector_pulse(cell, 1.0 / FPS) 
        
        // Activate pulse if hooked and cooldown is ready
        if cell.can_pulse && cell.pulse_cooldown <= 0 {
            for &predator in cells {
                if predator.type == .Predator && predator.is_hooking && predator.hook_target == cell {
                    cell.is_pulsing = true
                    cell.pulse_radius = 0
                    break
                }
            }
        }

        // TODO: Manual activation for testing (remove this in the final version)
        if rl.IsKeyPressed(.SPACE) && cell.pulse_cooldown <= 0 {
            cell.is_pulsing = true
            cell.pulse_radius = 0
        }
    }

    if DEBUG_MODE {
        append(&debug_info, fmt.tprintf("Cell %d: Type=%v, Energy=%.2f, Position=(%.2f, %.2f)", 
                                        cell_index(cell), cell.type, cell.energy, cell.center.x, cell.center.y))
    }

    // Gradual size adjustment
    adjust_cell_size(cell)
   
    // Check collision with hazards
    check_hazard_collisions(cell)

    // Predator eats collector and reproduces
    if cell.type == .Predator {
        handle_predator_eating(cell)
    }
}

update_cell_movement :: proc(cell: ^Cell, move_speed: f32) {
    if cell.type == .Predator {
        nearest_collector: ^Cell = nil
        min_distance := f32(math.F32_MAX)
        
        for &other in cells {
            if other.type == .Collector {
                diff := other.center - cell.center
                // Adjust diff for wrap-around
                if abs(diff.x) > SCREEN_WIDTH / 2 {
                    diff.x = -sign(diff.x) * (SCREEN_WIDTH - abs(diff.x))
                }
                if abs(diff.y) > SCREEN_HEIGHT / 2 {
                    diff.y = -sign(diff.y) * (SCREEN_HEIGHT - abs(diff.y))
                }
                dist := rl.Vector2Length(diff)
                
                // Only consider collectors within the ping radius
                if dist < min_distance && dist <= MAX_PING_RADIUS {
                    min_distance = dist
                    nearest_collector = &other
                }
            }
        }

        if nearest_collector != nil {
            direction := nearest_collector.center - cell.center
            // Adjust direction for wrap-around
            if abs(direction.x) > SCREEN_WIDTH / 2 {
                direction.x = -sign(direction.x) * (SCREEN_WIDTH - abs(direction.x))
            }
            if abs(direction.y) > SCREEN_HEIGHT / 2 {
                direction.y = -sign(direction.y) * (SCREEN_HEIGHT - abs(direction.y))
            }
            
            // Check if the predator should start hooking
            if !cell.is_hooking && min_distance <= cell.hook_max_length {
                cell.is_hooking = true
                cell.hook_target = nearest_collector
                cell.hook_position = cell.center
                cell.hook_length = 0
            }
            
            if !cell.is_hooking {
                cell.move_direction = rl.Vector2Normalize(direction) * move_speed * 1.5 // Move 50% faster towards collector
            } else {
                // If hooking, move slower
                cell.move_direction = rl.Vector2Normalize(direction) * move_speed * 0.5
            }
        } else {
            // Choose new random direction if no collector is found within ping radius
            angle := rand.float32_range(0, 2 * math.PI)
            cell.move_direction = {math.cos_f32(angle), math.sin_f32(angle)}
            cell.move_direction *= move_speed
        }
    } else {
        if cell.move_timer == 0 {
            angle := rand.float32_range(0, 2 * math.PI)
            cell.move_direction = {math.cos_f32(angle), math.sin_f32(angle)}
            cell.move_direction *= move_speed * (1 + 0.2 * math.sin_f32(f32(cell.behavior_seed)))
        }
    }

    // Avoid other cells
    for &other in cells {
        if &other != cell {
            diff := cell.center - other.center
            // Adjust diff for wrap-around
            if abs(diff.x) > SCREEN_WIDTH / 2 {
                diff.x = -sign(diff.x) * (SCREEN_WIDTH - abs(diff.x))
            }
            if abs(diff.y) > SCREEN_HEIGHT / 2 {
                diff.y = -sign(diff.y) * (SCREEN_HEIGHT - abs(diff.y))
            }
            dist := rl.Vector2Length(diff)
            if dist < AVOIDANCE_DISTANCE {
                avoidance := diff * move_speed / dist
                cell.move_direction += avoidance
            }
        }
    }

    // Move towards nearest food if collector and energy is low
    if cell.type == .Collector && cell.energy < MAX_ENERGY * 0.3 {
        nearest_food := find_nearest_food(cell)
        if nearest_food != nil {
            direction := nearest_food.position - cell.center
            // Adjust direction for wrap-around
            if abs(direction.x) > SCREEN_WIDTH / 2 {
                direction.x = -sign(direction.x) * (SCREEN_WIDTH - abs(direction.x))
            }
            if abs(direction.y) > SCREEN_HEIGHT / 2 {
                direction.y = -sign(direction.y) * (SCREEN_HEIGHT - abs(direction.y))
            }
            cell.move_direction = direction * move_speed / rl.Vector2Length(direction)
        }
    }

    cell.center += cell.move_direction
    cell.center = wrap_position(cell.center)
    cell.move_timer += 1

    if cell.move_timer >= MOVE_DURATION + int(10 * math.sin_f32(f32(cell.behavior_seed))) {
        cell.is_scanning = cell.type == .Collector  // Only collectors scan
        cell.scan_timer = 0
        cell.scan_angle = -90
    }
}

update_hook :: proc(cell: ^Cell) {
    if !cell.is_hooking do return

    direction := cell.hook_target.center - cell.center
    // Adjust direction for wrap-around
    if abs(direction.x) > SCREEN_WIDTH / 2 {
        direction.x = -sign(direction.x) * (SCREEN_WIDTH - abs(direction.x))
    }
    if abs(direction.y) > SCREEN_HEIGHT / 2 {
        direction.y = -sign(direction.y) * (SCREEN_HEIGHT - abs(direction.y))
    }
    normalized_direction := rl.Vector2Normalize(direction)

    cell.hook_position += normalized_direction * HOOK_SPEED
    cell.hook_length += HOOK_SPEED

    if cell.hook_length >= cell.hook_max_length {
        cell.is_hooking = false
        cell.hook_target = nil
        return
    }

    if rl.CheckCollisionCircles(cell.hook_position, 5, cell.hook_target.center, cell.hook_target.size / 2) {
        // Hook connected, pull the collector and drain energy
        cell.hook_target.center = linalg.lerp(cell.hook_target.center, cell.center, 0.1)

        // Check if the collector is pulsing
        if cell.hook_target.is_pulsing {
            // Calculate pulse force
            pulse_force := PULSE_FORCE * (1 - cell.hook_target.pulse_radius / MAX_PULSE_RADIUS)
            pulse_direction := rl.Vector2Normalize(cell.center - cell.hook_target.center)
            
            // Apply pulse force to predator
            cell.center += pulse_direction * pulse_force
            
            // Transfer 50% of predator's energy to collector
            energy_transfer := cell.energy * 0.5
            cell.energy -= energy_transfer
            cell.hook_target.energy += energy_transfer
            
            // Clamp energies to valid range
            cell.energy = clamp(cell.energy, 0, MAX_ENERGY)
            cell.hook_target.energy = clamp(cell.hook_target.energy, 0, MAX_ENERGY)
            
            // Set the draining predator and start energy drain effect
            cell.hook_target.draining_predator = cell
            cell.hook_target.is_draining = true
            cell.hook_target.drain_timer = PREDATOR_DRAIN_TIMER * FPS
            
            // Break the hook connection
            cell.is_hooking = false
            cell.hook_target = nil
        } else {
            // Normal energy drain if not pulsing
            energy_drained := min(ENERGY_DRAIN_RATE, cell.hook_target.energy)
            cell.hook_target.energy -= energy_drained
            cell.energy += energy_drained
            
            // Ensure energy levels stay within bounds
            cell.energy = min(cell.energy, MAX_ENERGY)
            cell.hook_target.energy = max(cell.hook_target.energy, 0)

            if rl.CheckCollisionCircles(cell.center, cell.size / 2, cell.hook_target.center, cell.hook_target.size / 2) {
                // Collector caught, trigger eating behavior
                handle_predator_eating(cell)
                cell.is_hooking = false
                cell.hook_target = nil
            }
        }
    }
}
update_predator_ping :: proc(cell: ^Cell, dt: f32) {
    if cell.type != .Predator do return

    cell.ping_cooldown -= dt

    if cell.ping_cooldown <= 0 {
        cell.is_pinging = true
        cell.ping_radius = 0
        cell.ping_cooldown = PING_INTERVAL
    }

    if cell.is_pinging {
        cell.ping_radius += PING_SPEED
        if cell.ping_radius > MAX_PING_RADIUS {
            cell.is_pinging = false
            cell.ping_radius = MAX_PING_RADIUS
        }
    }
}

wrap_position :: proc(position: rl.Vector2) -> rl.Vector2 {
    wrapped := position
    if wrapped.x < 0 {
        wrapped.x += f32(SCREEN_WIDTH)
    } else if wrapped.x >= f32(SCREEN_WIDTH) {
        wrapped.x -= f32(SCREEN_WIDTH)
    }
    
    if wrapped.y < 0 {
        wrapped.y += f32(SCREEN_HEIGHT)
    } else if wrapped.y >= f32(SCREEN_HEIGHT) {
        wrapped.y -= f32(SCREEN_HEIGHT)
    }
    
    return wrapped
}

update_collector_pulse :: proc(cell: ^Cell, dt: f32) {
    if cell.type != .Collector do return

    if cell.pulse_cooldown > 0 {
        cell.pulse_cooldown -= dt
        if cell.pulse_cooldown < 0 {
            cell.pulse_cooldown = 0
        }
    }

    if cell.is_pulsing {
        cell.pulse_radius += PULSE_SPEED * dt
        if cell.pulse_radius > MAX_PULSE_RADIUS {
            cell.is_pulsing = false
            cell.pulse_radius = 0
            cell.pulse_cooldown = PULSE_COOLDOWN
        }
    }
}

update_cell_scanning :: proc(cell: ^Cell) {
    cell.scan_timer += 1
    cell.scan_angle += f32(SCAN_ANGLE) / (f32(SCAN_DURATION) * (1 + 0.2 * math.cos_f32(f32(cell.behavior_seed))))

    if cell.type == .Collector {
        check_food_collision(cell)
    }

    if cell.scan_timer >= SCAN_DURATION + int(10 * math.cos_f32(f32(cell.behavior_seed))) {
        cell.is_scanning = false
        cell.move_timer = 0
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

        if DEBUG_MODE && food.being_pulled {
            append(&debug_info, fmt.tprintf("Food being pulled: Tier=%v, Size=%.2f, Position=(%.2f, %.2f)", 
                                            food.tier, food.size, food.position.x, food.position.y))
        }

        if rl.CheckCollisionCircleRec(
            food.position,
            food.size,
            {food.target_collector.center.x - food.target_collector.size/2,
                food.target_collector.center.y - food.target_collector.size/2,
                food.target_collector.size,
                food.target_collector.size}) 
        {
            energy_gain: f32
            if food.tier == .Golden {
                energy_gain = 200  // Golden food gives 200 energy
                food.target_collector.evolution_trait = EvolutionTrait(rand.int31_max(len(EvolutionTrait) - 1) + 1)
            } else {
                energy_gain = food_tier_properties[food.tier].energy
            }
            
            food.target_collector.energy += energy_gain
            if food.target_collector.energy > MAX_ENERGY {
                food.target_collector.energy = MAX_ENERGY
            }
            
            if DEBUG_MODE {
                append(&debug_info, fmt.tprintf("Cell gained %.0f energy from %v food", energy_gain, food.tier))
            }
            
            reset_food(food)
        }
    }
}

handle_cell_reproduction :: proc(cell: ^Cell) {
    if cell.type == .Collector && cell.energy >= 99 {
        new_cell := create_cell(.Collector)
        new_cell.center = cell.center
        new_cell.energy = 30
        new_cell.size = cell.size
        cell.energy = 70
        append(&cells, new_cell)
        fmt.printf("---------------New collector spawned. Total cells: %d\n", len(cells))
    }
}

adjust_cell_size :: proc(cell: ^Cell) {
    if cell.size < cell.target_size {
        cell.size += GROWTH_AMOUNT
    } else if cell.size > cell.target_size {
        cell.size -= GROWTH_AMOUNT
    }
    cell.size = clamp(cell.size, MIN_CELL_SIZE, MAX_CELL_SIZE)
}

check_hazard_collisions :: proc(cell: ^Cell) {
    for hazard in hazards {
        if rl.CheckCollisionCircles(cell.center, cell.size/2, hazard.position, hazard.radius) {
            cell.energy -= 1  // Drain energy when in contact with hazard
            if cell.energy < 0 do cell.energy = 0
        }
    }
}

handle_predator_eating :: proc(cell: ^Cell) {
    for i := 0; i < len(cells); {
        other := &cells[i]
        if other.type == .Collector && rl.CheckCollisionCircles(cell.center, cell.size/2, other.center, other.size/2) {
            energy_gained := other.energy * 0.75  
            cell.energy += energy_gained
            
            fmt.printf("DEBUG: Predator eating collector. Initial energy: %.2f, Energy gained: %.2f\n", 
                       cell.energy - energy_gained, energy_gained)
            
            if cell.energy > MAX_ENERGY {
                cell.energy = MAX_ENERGY
                fmt.printf("DEBUG: Predator energy capped at MAX_ENERGY: %.2f\n", cell.energy)
            }
            
            // Remove the eaten collector
            ordered_remove(&cells, i)
            
            fmt.printf("Collector eaten. Predator energy increased. Total cells: %d\n", len(cells))
            break // Only eat one collector per update
        } else {
            i += 1
        }
    }
}

evolve_cell :: proc(cell: ^Cell) {
    cell.evolution_trait = EvolutionTrait(rand.int31_max(len(EvolutionTrait) - 1) + 1)
    cell.energy -= EVOLUTION_THRESHOLD
}

find_nearest_food :: proc(cell: ^Cell) -> ^FoodCell {
    nearest_food: ^FoodCell = nil
    min_distance := f32(math.F32_MAX)

    for &food in food_cells {
        if food.active {
            diff := food.position - cell.center
            // Adjust diff for wrap-around
            if abs(diff.x) > SCREEN_WIDTH / 2 {
                diff.x = -sign(diff.x) * (SCREEN_WIDTH - abs(diff.x))
            }
            if abs(diff.y) > SCREEN_HEIGHT / 2 {
                diff.y = -sign(diff.y) * (SCREEN_HEIGHT - abs(diff.y))
            }
            distance := rl.Vector2Length(diff)
            if distance < min_distance {
                min_distance = distance
                nearest_food = &food
            }
        }
    }

    return nearest_food
}

check_food_collision :: proc(cell: ^Cell) {
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


reset_food :: proc(food: ^FoodCell) {
    new_food := create_random_food()
    food^ = new_food
}

draw_laser :: proc(cell: Cell, center: rl.Vector2) {
    base_direction := rl.Vector2{1, 0}
    scan_direction := rl.Vector2Rotate(base_direction, math.to_radians_f32(cell.scan_angle))
    move_angle := math.atan2_f32(cell.move_direction.y, cell.move_direction.x)
    final_direction := rl.Vector2Rotate(scan_direction, move_angle)
    laser_length := BASE_LASER_LENGTH * math.pow(cell.size / SQUARE_SIZE, 0.5) * (cell.evolution_trait == .LongLaser ? 1.5 : 1)
    laser_end := center + final_direction * laser_length
    laser_color := rl.ColorAlpha(rl.SKYBLUE, cell.energy / MAX_ENERGY)
    rl.DrawLineEx(
        center,
        laser_end,
        2,
        laser_color,
    )
}

cell_index :: proc(cell: ^Cell) -> int {
    for &c, i in cells {
        if &c == cell do return i
    }
    return -1
}

cleanup :: proc() {
    delete(cells)
    delete(food_cells)
    delete(debug_info)
    rl.CloseWindow()
}


// Helper functions
clamp :: proc(value, min, max: f32) -> f32 {
    if value < min do return min
    if value > max do return max
    return value
}

sign :: proc(x: f32) -> f32 {
    if x < 0 do return -1
    if x > 0 do return 1
    return 0
}