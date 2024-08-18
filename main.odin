package main

import "core:fmt"
import rl "vendor:raylib"

main :: proc() {
    rl.InitWindow(800, 450, "basic window")

    rl.SetTargetFPS(60)

    for rl.WindowShouldClose() == false {
        rl.BeginDrawing()

        rl.ClearBackground(rl.RAYWHITE)
        rl.DrawText("first window!", 190, 200, 20, rl.LIGHTGRAY)

        rl.EndDrawing()
    }

    rl.CloseWindow()
}