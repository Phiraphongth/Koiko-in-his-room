# Kopiko in his room

เกม 3D แนวสยองขวัญ/ปริศนา สร้างด้วย **Godot 4.7** ได้แรงบันดาลใจจาก Alice in Borderland
ผู้เล่นตื่นขึ้นมาในห้องของตัวเองแล้วถูกบังคับให้เล่น "เกม" 4 ด่านเพื่อเอาชีวิตรอด

> A 3D horror/puzzle game made in Godot 4.7, inspired by Alice in Borderland.

## ด่านในเกม

| ด่าน | ชื่อ | แนวการเล่น | เวลา |
|---|---|---|---|
| บทนำ | The Room | ตื่นในห้อง หาโทรศัพท์ เดินตามไพ่ไปลงทะเบียน | — |
| 1 ♦♣ | The Maze of Whispers | เขาวงกตที่เปลี่ยนทางทุก 35 วินาที หาหินกระซิบ 3 ก้อน หลบสัญญาณเตือนภัย | 6 นาที |
| 2 ♠♥10 | The Blind Stalker | หลบปีศาจตาบอดที่ล่าด้วยเสียงและเสียงหัวใจ หาคีย์การ์ด 3 ใบ | 10 นาที |
| 3 ♠5 | Vertical Abyss | ปีนตึก 40 เมตรหนีกรด พาร์กัวร์ ปีนผา โหนราว | 10 นาที |
| 4 ♣9 | The Pressure Valve | วิ่งคนเดียวระหว่างห้องแผนผังกับห้องวาล์ว คุมแรงดันให้นิ่งขณะแก๊สรั่ว | 5 นาที |

ฉากจบมี 2 แบบ ขึ้นกับผลงานในด่าน 4: ออกมาได้โดยแรงดันระเบิดไม่เกิน 1 ครั้งคือฉากจบที่ดี

## วิธีเล่น

1. เปิด Godot 4.7 แล้ว Import โฟลเดอร์นี้ (หรือเปิดไฟล์ `project.godot`)
2. กด F5 เพื่อเริ่มจากเมนูหลัก

**ปุ่มควบคุม:** WASD เดิน · Shift วิ่ง · C ย่อตัว · Space กระโดด · E โต้ตอบ · Q กลั้นหายใจ · F ไฟฉาย · คลิกซ้าย ขว้าง · คลิกขวา เล็ง · R สลับของ · Esc หยุดเกม

**ภาษา:** ไทย / อังกฤษ สลับได้ในเมนูตั้งค่า

## โครงสร้างโปรเจกต์

```
autoload/      EventBus, GameManager, SettingsManager, LevelLoader, SceneTransition
core/          LevelBase, Interactable, InputConfig, Layers
player/        ตัวผู้เล่น + ความสามารถ (ขว้าง ปีน/โหน ไฟฉาย) + อนิเมชัน
gameplay/      ชิ้นส่วนที่ใช้ซ้ำ: ปีศาจ, NPCController, ประตู, กำแพงเลื่อน, เลเซอร์, แป้นกด ฯลฯ
ui/            HUD, เมนูตั้งค่า, เอฟเฟกต์จอ, ตัวช่วยแปลภาษา
audio/         เครื่องสังเคราะห์เสียงทั้งหมด (ไม่มีไฟล์เสียงจริง)
localization/  ui.csv (keys, en, th)
scenes/        เมนู, บทนำ, 4 ด่าน, ฉากจบ
tools/         สคริปต์สร้างฉากและอนิเมชันอัตโนมัติ
```

## หมายเหตุสำหรับคนแก้ไขต่อ

- **ฉากและอนิเมชันถูกสร้างจากโค้ด** ไฟล์ `scenes/**/level_*.tscn`, `main_menu.tscn`, `hub.tscn`
  และ `player/animations/player_animations.res` สร้างจากสคริปต์ใน `tools/`
  ถ้ารันสคริปต์สร้างใหม่ สิ่งที่แก้ใน editor จะถูกเขียนทับ ให้แก้ที่ตัวสร้างแทน

  ```bash
  godot --headless --path . res://tools/scene_builder/build_level_2.tscn
  ```

- **เสียงทุกเสียงสังเคราะห์ในโค้ด** ดู `audio/procedural_audio.gd` ถ้าจะเปลี่ยนไปใช้ไฟล์เสียงจริง
  ให้คืนค่า `AudioStream` ที่โหลดจากไฟล์ใน `get_stream()`
- **ข้อความในเกม** ใช้คีย์จาก `localization/ui.csv` ข้อความที่ตั้งจากโค้ดต้องผ่าน `Localization.set_text()`

## เวอร์ชันเว็บ (itch.io)

โปรเจกต์ตั้งค่าให้ใช้ renderer **Compatibility** (WebGL 2) เพราะเบราว์เซอร์รัน Forward+ ไม่ได้
สิ่งที่เห็นใน editor จึงตรงกับที่ผู้เล่นบน itch.io เห็น

- **Export:** Project → Export → `Web (itch.io)` → Export Project ไปที่ `builds/web/index.html`
  แล้ว zip ไฟล์ทั้งหมดในโฟลเดอร์นั้น (ให้ `index.html` อยู่ชั้นบนสุดของ zip)
- **ตั้งค่าบน itch.io:** Kind of project = HTML · ติ๊ก "This file will be played in the browser"
  · Viewport 1280 × 720 · เปิด "Fullscreen button" · ไม่ต้องเปิด SharedArrayBuffer (build ไม่ใช้ threads)
- **ความละเอียด:** ขนาดฐาน UI = 1280 × 720 (stretch `canvas_items` / `expand`)
  บนเว็บ canvas ปรับตามหน้าเว็บอัตโนมัติ ส่วน "ความละเอียดภาพ 3D" ในเมนูตั้งค่า (50–100%, เว็บเริ่มที่ 75%)
  ลดความละเอียดเฉพาะฉาก 3D เพื่อให้ลื่น UI ยังคมเหมือนเดิม
- **เอฟเฟกต์ที่ Compatibility ไม่มี:** volumetric fog, FogVolume, SSAO, SSR
  `SettingsManager._adapt_environment()` แทน volumetric fog ด้วย distance fog ให้อัตโนมัติ
  และด่าน 4 ใช้ fog สีเขียวแทนแก๊ส ถ้าสลับกลับไปใช้ Forward+ (เช่นทำ build Windows) เอฟเฟกต์เดิมกลับมาเอง
- **ฟอนต์:** `fonts/game_font.tres` (Noto Sans Thai + สัญลักษณ์ไพ่จาก DejaVu) เพราะบนเว็บไม่มีฟอนต์ระบบให้ยืม
  ถ้าเพิ่มข้อความที่มีสัญลักษณ์แปลกใหม่ ให้เช็คว่าฟอนต์มีตัวนั้น
- **ข้อควรระวังเวลาเพิ่มโมเดล/ระบบ:** texture ไม่เกิน 1024 px, ไฟในบริเวณเดียวกันไม่เกิน 16 ดวง
  (`limits/opengl/max_lights_per_object`), ไฟที่มีเงาให้น้อยที่สุด, อย่าใช้ฟีเจอร์ที่มีเฉพาะ Forward+

## เครดิต

- โมเดลตัวละคร: Simple PSX Character โดย [JashiPSX](https://jashi-psx.itch.io)
- เอนจิน: [Godot Engine](https://godotengine.org)
- ฟอนต์: Noto Sans Thai (SIL OFL 1.1) และ DejaVu Sans (subset) — ดู `fonts/LICENSES.txt`
