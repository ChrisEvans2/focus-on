# 阶段提醒宠物素材

此奶白小猫为旧版本，已由 [斜探头圆角团子](phase-peek-generation.md) 替换；旧图片保留作参考，不再随 App 打包。

- 工具：内置 `image_gen`；接口未提供底层模型选择，未声称使用特定型号。
- 参考：用户确认的奶白小猫提醒概念图。
- 原始输出：`macos/Sources/FocusOn/Resources/phase-pet.png`，1774 × 887，透明 RGBA，两帧横排。
- 接入：保留生成文件原样，通过 `PhaseReminderView.spriteFrames` 选择微笑与眨眼区域，统一显示位置和大小；资源通过 SwiftPM 随 App 打包。

## 生成提示词

Use case: stylized-concept. Asset type: production raster two-frame animation sprite atlas for desktop reminder pet. The supplied image is a CHARACTER AND RENDERING STYLE REFERENCE ONLY: preserve precisely the adorable cream-white plump cat, warm delicate dark brown outline, tiny pale peach inner ears, soft peach cheeks, little two front paws, creamy softly shaded dimensional surface and gentle paper-like rendering of the cat in the bottom middle reference panel. The user approved that cat and explicitly rejected a simplified code-drawn/vector replacement. Generate one transparent PNG atlas with exactly TWO EQUAL SQUARE CELLS side by side, horizontal 2:1 canvas, ideally 1536 x 768 pixels. No grid is visible. Each half is an animation frame: same cat, frontal symmetrical head, same body silhouette and paw positions, same lighting, same scale and alignment. Cat occupies about 76 percent of its cell width and 80 percent of its cell height, perfectly centered with generous transparent padding. LEFT frame: eyes like ^ ^ and a tiny flat underscore mouth, expression ^_^. RIGHT frame: exact duplicate of left with ONLY the viewer-right eye changed into a short straight horizontal closed-wink stroke, expression ^_-. Keep the head position and pose absolutely identical in both frames so they animate without jitter; do NOT tilt the head or change the silhouette. The entire character including ears and paws is visible and isolated. Crucial: genuine transparent alpha background, not a checkerboard painted into the image, no white rectangle, no monitor, no desktop, no speech bubble, no buttons, no text, no labels, no arrows, no scenery, no ground plane, no shadow outside the character. Preserve the reference's soft dimensional painted quality; do not flatten into a vector icon or geometric logo. Output only the finished two-frame transparent sprite atlas.
