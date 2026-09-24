extends RefCounted
const ANALYSIS := "continuous_mixed_audio_pitch_shape_60ms_v1"
const PIGSTEP = preload("res://scripts/characters/我的世界/cactus_note/shape_pigstep.gd")
const OTHERSIDE = preload("res://scripts/characters/我的世界/cactus_note/shape_otherside.gd")
const CAT = preload("res://scripts/characters/我的世界/cactus_note/shape_cat.gd")
const CREATOR = preload("res://scripts/characters/我的世界/cactus_note/shape_creator.gd")
const PRECIPICE = preload("res://scripts/characters/我的世界/cactus_note/shape_precipice.gd")
const RELIC = preload("res://scripts/characters/我的世界/cactus_note/shape_relic.gd")
const DATA:Dictionary = {"pigstep":PIGSTEP.DATA,"otherside":OTHERSIDE.DATA,"cat":CAT.DATA,"creator":CREATOR.DATA,"precipice":PRECIPICE.DATA,"relic":RELIC.DATA}
