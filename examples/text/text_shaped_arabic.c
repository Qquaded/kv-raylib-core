/*******************************************************************************************
*
*   raylib [text] example - Shaped text with HarfBuzz (Arabic, BiDi, ligatures)
*
*   Example complexity rating: [★★☆☆] 2/4
*
*   FontShaper wraps FreeType + HarfBuzz so scripts like Arabic are rendered with
*   correct joining (initial / medial / final forms) and right-to-left order.
*   Unlike Font + DrawText which draws each Unicode codepoint in its isolated form.
*
*   NOTE: The font used here must contain the glyphs for the scripts you want to draw.
*         Latin-only fonts will still render English text but show .notdef boxes for Arabic.
*
*   Example originally created with raylib 6.0, last time updated with raylib 6.0
*
*   Example licensed under an unmodified zlib/libpng license, which is an OSI-certified,
*   BSD-like license that allows static linking with closed source software
*
*   Copyright (c) 2025 Ramon Santamaria (@raysan5)
*
********************************************************************************************/

#include "raylib.h"

int main(void)
{
    const int screenWidth = 900;
    const int screenHeight = 400;

    InitWindow(screenWidth, screenHeight, "raylib [text] example - shaped text (HarfBuzz)");

    // Load a font that contains both Latin and Arabic glyphs.
    // Replace the path with any TTF/OTF that covers the scripts you want.
    FontShaper *shaper = LoadFontShaper("resources/NotoNaskhArabicUI-Regular.ttf", 36);

    const char *englishText = "Hello, raylib!";
    const char *arabicText  = "مرحبا بالعالم";                // "Hello, world"
    const char *greetingAr  = "السلام عليكم";                 // "Peace be upon you"
    const char *mixedText   = "raylib يدعم النصوص العربية الآن";  // "raylib supports Arabic now"

    SetTargetFPS(60);

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);

            DrawText("Shaped text via FontShaper (FreeType + HarfBuzz):", 20, 20, 20, DARKGRAY);

            if (IsFontShaperValid(shaper))
            {
                DrawTextShaped(shaper, englishText, (Vector2){ 20.0f,  70.0f }, 36.0f, 0.0f, MAROON);
                DrawTextShaped(shaper, arabicText,  (Vector2){ 20.0f, 130.0f }, 36.0f, 0.0f, DARKBLUE);
                DrawTextShaped(shaper, greetingAr,  (Vector2){ 20.0f, 190.0f }, 36.0f, 0.0f, DARKGREEN);
                DrawTextShaped(shaper, mixedText,   (Vector2){ 20.0f, 250.0f }, 36.0f, 0.0f, DARKPURPLE);
            }
            else
            {
                DrawText("FontShaper failed to load. Check the font path.", 20, 130, 20, RED);
            }

            DrawText("HarfBuzz handles RTL, joining, and script auto-detection.",
                     20, screenHeight - 30, 16, GRAY);
        EndDrawing();
    }

    UnloadFontShaper(shaper);
    CloseWindow();

    return 0;
}
