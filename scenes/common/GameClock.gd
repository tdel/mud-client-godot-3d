class_name GameClock
## Horloge de jeu partagée, en secondes : somme des delta de rendu, et non l'horloge murale
## (Time.get_ticks_msec). Les animations continues (portails, téléporteurs, lueurs de lampes,
## aiguille de recharge) suivent ainsi le temps du jeu, y compris sous Movie Maker
## (--write-movie, voir tools/demo_video), qui rend à pas fixe, bien plus lentement que le
## temps réel : avec l'horloge murale, ces effets y tournaient en accéléré.
##
## Mise à jour paresseuse au premier appel de chaque image ; les images sans aucun appel sont
## rattrapées avec le delta courant (exact à pas fixe, très proche sinon).

static var _seconds := 0.0
static var _frame := -1


static func now() -> float:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		var tree := Engine.get_main_loop() as SceneTree
		if _frame >= 0 and tree != null:
			_seconds += tree.root.get_process_delta_time() * float(frame - _frame)
		_frame = frame
	return _seconds


static func now_msec() -> float:
	return now() * 1000.0
