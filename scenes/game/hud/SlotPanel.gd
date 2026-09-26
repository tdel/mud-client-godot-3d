extends Panel
## Panel de slot dont l'infobulle accepte le BBCode (voir UITheme.make_rich_tooltip) — pour
## les slots non glissables (liste de la boutique) ; les icônes glissables passent par
## DraggableIcon, qui fait de même.


func _make_custom_tooltip(for_text: String) -> Object:
	return UITheme.make_rich_tooltip(for_text)
