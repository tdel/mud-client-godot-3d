class_name MonsterCatalog
extends RefCounted
## Nom de monstre serveur (MonsterTemplate.name, voir data/monsters.xml côté backend) ->
## fiche visuelle MonsterModel. Le serveur n'envoie que le nom (EntityView.name) : clé en
## minuscules, comparée au nom normalisé. Un monstre absent d'ici reste une capsule rouge
## (voir Game3D._make_entity_node).
##
## Ajouter un monstre : déposer son .glb dans assets/monsters/<monstre>/, créer la .tres
## MonsterModel à côté (nom des clips, échelle), puis l'enregistrer ci-dessous — plusieurs
## noms peuvent partager une même fiche (variantes d'un même animal). Les monstres L2 de la
## région de Gludio ont chacun leur fiche, écrite (avec le bloc marqué ci-dessous) par
## tools/monster_gen/build_monster_models.py : y ajouter le monstre puis relancer le script.

const MODELS := {
	"fox": preload("res://assets/monsters/fox/fox.tres"),
	"brown keltir": preload("res://assets/monsters/keltir/brown_keltir.tres"),
	# --- Fiches générées par tools/monster_gen/build_monster_models.py ---
	"young keltir": preload("res://assets/monsters/keltir/young_keltir.tres"),
	"elder keltir": preload("res://assets/monsters/keltir/elder_keltir.tres"),
	"wolf": preload("res://assets/monsters/keltir/wolf.tres"),
	"elder wolf": preload("res://assets/monsters/keltir/elder_wolf.tres"),
	"shadow beast": preload("res://assets/monsters/keltir/shadow_beast.tres"),
	"elpy": preload("res://assets/monsters/elpy/elpy.tres"),
	"gremlin": preload("res://assets/monsters/gremlin/gremlin.tres"),
	"giant toad": preload("res://assets/monsters/toad/giant_toad.tres"),
	"toad lord": preload("res://assets/monsters/toad/toad_lord.tres"),
	"orc": preload("res://assets/monsters/orc/orc.tres"),
	"orc grunt": preload("res://assets/monsters/orc/orc_grunt.tres"),
	"orc archer": preload("res://assets/monsters/orc/orc_archer.tres"),
	"orc fighter": preload("res://assets/monsters/orc/orc_fighter.tres"),
	"goblin": preload("res://assets/monsters/orc/goblin.tres"),
	"goblin scout": preload("res://assets/monsters/orc/goblin_scout.tres"),
	"vuku orc": preload("res://assets/monsters/orc/vuku_orc.tres"),
	"vuku orc archer": preload("res://assets/monsters/orc/vuku_orc_archer.tres"),
	"werewolf": preload("res://assets/monsters/werewolf/werewolf.tres"),
	"werewolf hunter": preload("res://assets/monsters/werewolf/werewolf_hunter.tres"),
	"tumran bugbear warrior": preload("res://assets/monsters/bugbear/tumran_bugbear_warrior.tres"),
	"veelan bugbear": preload("res://assets/monsters/bugbear/veelan_bugbear.tres"),
	"veelan bugbear warrior": preload("res://assets/monsters/bugbear/veelan_bugbear_warrior.tres"),
	"bugbear raider": preload("res://assets/monsters/bugbear/bugbear_raider.tres"),
	"ratman spy": preload("res://assets/monsters/ratman/ratman_spy.tres"),
	"ratman hunter": preload("res://assets/monsters/ratman/ratman_hunter.tres"),
	"ratman sub chieftain": preload("res://assets/monsters/ratman/ratman_sub_chieftain.tres"),
	"ratman chieftain": preload("res://assets/monsters/ratman/ratman_chieftain.tres"),
	"sukar wererat chief": preload("res://assets/monsters/ratman/sukar_wererat_chief.tres"),
	"maille lizardman": preload("res://assets/monsters/lizardman/maille_lizardman.tres"),
	"maille lizardman scout": preload("res://assets/monsters/lizardman/maille_lizardman_scout.tres"),
	"maille lizardman guard": preload("res://assets/monsters/lizardman/maille_lizardman_guard.tres"),
	"maille lizardman warrior": preload("res://assets/monsters/lizardman/maille_lizardman_warrior.tres"),
	"maille lizardman shaman": preload("res://assets/monsters/lizardman/maille_lizardman_shaman.tres"),
	"maille lizardman matriarch": preload("res://assets/monsters/lizardman/maille_lizardman_matriarch.tres"),
	"ruin zombie": preload("res://assets/monsters/zombie/ruin_zombie.tres"),
	"ruin zombie leader": preload("res://assets/monsters/zombie/ruin_zombie_leader.tres"),
	"zombie soldier": preload("res://assets/monsters/zombie/zombie_soldier.tres"),
	"zombie warrior": preload("res://assets/monsters/zombie/zombie_warrior.tres"),
	"zombie lord crowl": preload("res://assets/monsters/zombie/zombie_lord_crowl.tres"),
	"skeleton tracker": preload("res://assets/monsters/skeleton/skeleton_tracker.tres"),
	"skeleton tracker leader": preload("res://assets/monsters/skeleton/skeleton_tracker_leader.tres"),
	"skeleton scout": preload("res://assets/monsters/skeleton/skeleton_scout.tres"),
	"skeleton bowman": preload("res://assets/monsters/skeleton/skeleton_bowman.tres"),
	"ruin spartoi": preload("res://assets/monsters/skeleton/ruin_spartoi.tres"),
	"raging spartoi": preload("res://assets/monsters/skeleton/raging_spartoi.tres"),
	"shield skeleton": preload("res://assets/monsters/skeleton/shield_skeleton.tres"),
	"skeleton infantryman": preload("res://assets/monsters/skeleton/skeleton_infantryman.tres"),
	"soul scavenger": preload("res://assets/monsters/skeleton/soul_scavenger.tres"),
	"horror mist ripper": preload("res://assets/monsters/wraith/horror_mist_ripper.tres"),
	"ruin imp": preload("res://assets/monsters/imp/ruin_imp.tres"),
	"ruin imp elder": preload("res://assets/monsters/imp/ruin_imp_elder.tres"),
	"scavenger bat": preload("res://assets/monsters/bat/scavenger_bat.tres"),
	"ruin bat": preload("res://assets/monsters/bat/ruin_bat.tres"),
	"giant mist leech": preload("res://assets/monsters/leech/giant_mist_leech.tres"),
	"gray ant": preload("res://assets/monsters/spider/gray_ant.tres"),
	"giant crimson ant": preload("res://assets/monsters/spider/giant_crimson_ant.tres"),
	"pinrul": preload("res://assets/monsters/spider/pinrul.tres"),
	"marsh spider": preload("res://assets/monsters/spider/marsh_spider.tres"),
	"giant araneid": preload("res://assets/monsters/spider/giant_araneid.tres"),
	"poison araneid": preload("res://assets/monsters/spider/poison_araneid.tres"),
	"king of the araneid": preload("res://assets/monsters/spider/king_of_the_araneid.tres"),
	"stinger wasp": preload("res://assets/monsters/wasp/stinger_wasp.tres"),
	"marsh stakato": preload("res://assets/monsters/stakato/marsh_stakato.tres"),
	"marsh stakato worker": preload("res://assets/monsters/stakato/marsh_stakato_worker.tres"),
	"marsh stakato soldier": preload("res://assets/monsters/stakato/marsh_stakato_soldier.tres"),
	"marsh stakato drone": preload("res://assets/monsters/stakato/marsh_stakato_drone.tres"),
	"stakato queen zyrnna": preload("res://assets/monsters/stakato/stakato_queen_zyrnna.tres"),
	"scavenger spider": preload("res://assets/monsters/spider/scavenger_spider.tres"),
	"moonstone beast": preload("res://assets/monsters/keltir/moonstone_beast.tres"),
	"scavenger wererat": preload("res://assets/monsters/ratman/scavenger_wererat.tres"),
	"arachnid tracker": preload("res://assets/monsters/spider/arachnid_tracker.tres"),
	"lycanthrope": preload("res://assets/monsters/werewolf/lycanthrope.tres"),
	"felim lizardman": preload("res://assets/monsters/lizardman/felim_lizardman.tres"),
	"felim lizardman scout": preload("res://assets/monsters/lizardman/felim_lizardman_scout.tres"),
	"felim lizardman warrior": preload("res://assets/monsters/lizardman/felim_lizardman_warrior.tres"),
	"red bear": preload("res://assets/monsters/bear/red_bear.tres"),
	"grizzly bear": preload("res://assets/monsters/bear/grizzly_bear.tres"),
	"gora werewolf": preload("res://assets/monsters/werewolf/gora_werewolf.tres"),
	"arachnid predator": preload("res://assets/monsters/spider/arachnid_predator.tres"),
	"ratman warrior": preload("res://assets/monsters/ratman/ratman_warrior.tres"),
	"ol mahum novice": preload("res://assets/monsters/olmahum/ol_mahum_novice.tres"),
	"ol mahum recruit": preload("res://assets/monsters/olmahum/ol_mahum_recruit.tres"),
	"ol mahum patrol": preload("res://assets/monsters/olmahum/ol_mahum_patrol.tres"),
	"ol mahum guard": preload("res://assets/monsters/olmahum/ol_mahum_guard.tres"),
	"ol mahum supplier": preload("res://assets/monsters/olmahum/ol_mahum_supplier.tres"),
	"ol mahum straggler": preload("res://assets/monsters/olmahum/ol_mahum_straggler.tres"),
	"ol mahum officer": preload("res://assets/monsters/olmahum/ol_mahum_officer.tres"),
	"ol mahum captain": preload("res://assets/monsters/olmahum/ol_mahum_captain.tres"),
	"hungry eye": preload("res://assets/monsters/eye/hungry_eye.tres"),
	"wandering eye": preload("res://assets/monsters/eye/wandering_eye.tres"),
	"greyclaw kutus": preload("res://assets/monsters/werewolf/greyclaw_kutus.tres"),
	"princess molrang": preload("res://assets/monsters/lizardman/princess_molrang.tres"),
	"specter": preload("res://assets/monsters/wraith/specter.tres"),
	"sorrow maiden": preload("res://assets/monsters/wraith/sorrow_maiden.tres"),
	"neer crawler": preload("res://assets/monsters/zombie/neer_crawler.tres"),
	"neer ghoul berserker": preload("res://assets/monsters/zombie/neer_ghoul_berserker.tres"),
	"strain": preload("res://assets/monsters/zombie/strain.tres"),
	"ghoul": preload("res://assets/monsters/zombie/ghoul.tres"),
	"amber basilisk": preload("res://assets/monsters/basilisk/amber_basilisk.tres"),
	"granite golem": preload("res://assets/monsters/golem/granite_golem.tres"),
	"dead seeker": preload("res://assets/monsters/keltir/dead_seeker.tres"),
	"hangman tree": preload("res://assets/monsters/tree/hangman_tree.tres"),
	"revenant of sir calibus": preload("res://assets/monsters/skeleton/revenant_of_sir_calibus.tres"),
	"guillotine, warden of the execution grounds": preload("res://assets/monsters/skeleton/guillotine_warden_of_the_execution_grounds.tres"),
	"tumran bugbear": preload("res://assets/monsters/bugbear/tumran_bugbear.tres"),
	"dire wolf": preload("res://assets/monsters/keltir/dire_wolf.tres"),
	"monster eye gazer": preload("res://assets/monsters/eye/monster_eye_gazer.tres"),
	"watchman of the plains": preload("res://assets/monsters/eye/watchman_of_the_plains.tres"),
	"cursed seer": preload("res://assets/monsters/eye/cursed_seer.tres"),
	"roughly hewn rock golem": preload("res://assets/monsters/golem/roughly_hewn_rock_golem.tres"),
	"delu lizardman supplier": preload("res://assets/monsters/lizardman/delu_lizardman_supplier.tres"),
	"delu lizardman special agent": preload("res://assets/monsters/lizardman/delu_lizardman_special_agent.tres"),
	"delu lizardman shaman": preload("res://assets/monsters/lizardman/delu_lizardman_shaman.tres"),
	"delu lizardman commander": preload("res://assets/monsters/lizardman/delu_lizardman_commander.tres"),
	# --- Fin des fiches générées ---
}


## Serviteurs invoqués (EntityView.model côté backend, data/summons/summons.xml) : chats
## tirés du renard recoloré, panthère du loup noirci ; "undead" (Corrupted Man) reste un
## mannequin humanoïde (aucune fiche).
const SUMMON_MODELS := {
	"cat_kat": preload("res://assets/monsters/summons/cat_kat.tres"),
	"cat_mew": preload("res://assets/monsters/summons/cat_mew.tres"),
	"cat_kai": preload("res://assets/monsters/summons/cat_kai.tres"),
	"panther": preload("res://assets/monsters/summons/panther.tres"),
}


static func summon_model(model: String) -> MonsterModel:
	return SUMMON_MODELS.get(model)


## Fiche du monstre `monster_name`, null si aucun modèle dédié.
static func model_for(monster_name: String) -> MonsterModel:
	return MODELS.get(monster_name.strip_edges().to_lower())
