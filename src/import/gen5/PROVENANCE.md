Nds, Narc, Lz, Graphics, Cells, Animation and Composer adapt AnimaEngine v1.0.0
container, decoding and rasterization algorithms, copyright (c) 2026 AnimaEngine
contributors, under MIT. Preserve the complete notice in ANIMAENGINE_LICENSE.

Reference: https://github.com/KillDaWill/AnimaEngine/tree/v1.0.0 (70547df).
Sources: nanr.c, nmcr.c, nmar.c, sprite_composer.c, ncgr.c, nclr.c, ncer.c, nanr.h.

The Lua port adds strict resource bounds, sparse indexed buffers, loop-prefix
timing and explicit capped cycles. Coordinates use symmetric nearest-neighbor
rounding. Source indices remain zero-based; Lua arrays are one-based. No ROM
data, extracted assets or native decoder binaries are included.
