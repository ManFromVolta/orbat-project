extends RefCounted
## Контракт скелета ORBAT.
##
## Имена костей, иерархия и ориентация осей берутся из SkeletonProfileHumanoid движка:
## T-поза, модель смотрит в +Z (как в glTF), левая сторона = +X, ось Y кости идёт вдоль кости
## к дочерней. Поэтому любые гуманоидные анимации (Blender, Mixamo, mocap) ретаргетятся через
## BoneMap без правок. Свои тут только пропорции (рост 1.75 м, 1 ед. = 1 м).
##
## Меняя таблицу, пересобери ресурсы: godot --headless --path godot -s tools/build_all.gd

const HEIGHT := 1.75
## Высота сустава стопы над землёй (подошва = 0).
const ANKLE_HEIGHT := 0.09

## [кость, родитель, смещение от родителя в ЛОКАЛЬНЫХ осях родителя]
## Родитель всегда стоит в таблице раньше потомка.
const BONES := [
	["Root", "", Vector3(0, 0, 0)],
	["Hips", "Root", Vector3(0, 0.92, 0)],
	["Spine", "Hips", Vector3(0, 0.10, 0)],
	["Chest", "Spine", Vector3(0, 0.12, 0)],
	["UpperChest", "Chest", Vector3(0, 0.13, 0)],
	["Neck", "UpperChest", Vector3(0, 0.17, 0)],
	["Head", "Neck", Vector3(0, 0.09, 0)],

	["LeftShoulder", "UpperChest", Vector3(0.05, 0.15, 0)],
	["LeftUpperArm", "LeftShoulder", Vector3(0, 0.14, 0)],
	["LeftLowerArm", "LeftUpperArm", Vector3(0, 0.30, 0)],
	["LeftHand", "LeftLowerArm", Vector3(0, 0.27, 0)],

	["RightShoulder", "UpperChest", Vector3(-0.05, 0.15, 0)],
	["RightUpperArm", "RightShoulder", Vector3(0, 0.14, 0)],
	["RightLowerArm", "RightUpperArm", Vector3(0, 0.30, 0)],
	["RightHand", "RightLowerArm", Vector3(0, 0.27, 0)],

	["LeftUpperLeg", "Hips", Vector3(0.09, 0, 0)],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(0, 0.43, 0)],
	["LeftFoot", "LeftLowerLeg", Vector3(0, 0.40, 0)],
	["LeftToes", "LeftFoot", Vector3(0, 0.15, 0)],

	["RightUpperLeg", "Hips", Vector3(-0.09, 0, 0)],
	["RightLowerLeg", "RightUpperLeg", Vector3(0, 0.43, 0)],
	["RightFoot", "RightLowerLeg", Vector3(0, 0.40, 0)],
	["RightToes", "RightFoot", Vector3(0, 0.15, 0)],
]
