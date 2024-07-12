# Reshade-shader for ASCII-art style rendering


Inspired by (and most configuration options copied from )  Garrett Gunnells [ASCII shader](https://github.com/GarrettGunnell/AcerolaFX/blob/main/Shaders/AcerolaFX_ASCII.fx).
I thought that explicitly detecting edges and replacing them with their matching characters was fine, but what if you could match any kind of character instead?
So that is what this shader does. Each 8x8 patch of the game gets its luminosity averaged, after which that luminosity acts as a key into the set of 64 implemented ASCII characters.
The luminosity value selects 16 out of the 64 characters for the next step. There the character that matches the original patch closest, pixel by pixel, replaces the patch. This way,
some simple form of shape and edge detection is automatically built-in to the shader, without any image processing.

![Screenshot of Nove Drift](https://github.com/aapo-kossi/Fine-ASCII-Shader/blob/main/screenshot-1.png)

![Another screenshot of Nove Drift](https://github.com/aapo-kossi/Fine-ASCII-Shader/blob/main/screenshot-2.png)
