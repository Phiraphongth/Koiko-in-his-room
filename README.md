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
| 4 ♣9 | The Pressure Valve | ร่วมมือกับ AI ที่อยู่คนละห้อง สื่อสารด้วยสัญลักษณ์ | 9 นาที |

ฉากจบมี 2 แบบ ขึ้นกับว่าคุณพาเพื่อน AI ออกมาด้วยหรือทิ้งเขาไว้ในด่าน 4

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

## เครดิต

- โมเดลตัวละคร: Simple PSX Character โดย [JashiPSX](https://jashi-psx.itch.io)
- เอนจิน: [Godot Engine](https://godotengine.org)
