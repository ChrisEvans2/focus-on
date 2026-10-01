# 斜探头阶段提醒

- 工具：内置 image_gen。
- 参考：用户确认的斜探头概念图；保留分神宠物的圆角团子、绿／黄绿和双眼造型。
- 原始素材：`macos/Sources/FocusOn/Resources/phase-peek.png`，1254 × 1254，透明 RGBA。
- 四帧：上排浅色微笑／眨眼，下排深色微笑／眨眼。生成图已经包含歪头与垂直裁切，App 不重画宠物。
- 屏幕内可见尺寸：约 160 × 220 点；图片右缘延伸到窗口裁切边界外 2 点，保持贴边。文本胶囊与宠物保持间隔。
- 原始输出不修改，App 通过图片区域选择与位置变化实现动画。原奶白小猫资源留作旧版本，已从应用资源中排除。

## 最终素材生成提示词

Generate a CLEAN FLAT 2D production PNG sprite sheet from the attached approved peeking-pet mockup. Exactly FOUR sprites in a 2x2 grid on genuine transparent alpha, square canvas. The pet silhouette is the LEFT HALF of a large softly rounded square tilted 25 degrees counterclockwise, cut off at a perfectly straight VERTICAL right edge as in the reference. Both eyes visible, and no mouth or anatomy. Match the approved shape and diagonally arranged eyes. Top left: SOLID flat muted green #496A5D with two warm-white caret eyes. Top right: exactly identical, right eye changed to a short white wink dash. Bottom left: exact same sprite shape recolored SOLID flat lime #D6E92F with black caret eyes. Bottom right: exact same lime shape with black caret and right dash. IDENTICAL silhouette, location, dimensions and crop in all cells. Each body centered in its cell with ample transparent padding, body about 55% cell width by 76% cell height. This must look like impeccably clean modern flat 2D cartoon game UI art, NOT a physical textured or painted object. Absolutely NO surface textures, mottling, grain, gradients, glow, cast shadows, roughness, light spill, outlines, distressed edges, or speckling. Silhouette boundary must be a smooth immaculate anti-aliased curve without any dots/flecks/fringe/residue outside. Right cut edge is perfectly vertical. No screen edges, backdrops, text, diagrams, labels, panels or speech capsules. Uniform flat color makes transparency clean. True transparent PNG only, never simulate transparency with a background/checkerboard. The four clean tilted cut-off rounded blobs with their two expression variants and two colors ONLY.
