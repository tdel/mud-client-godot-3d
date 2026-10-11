extends RefCounted
## Géographie commune des cartes de la région de Gludio (façon Lineage 2), partagée par
## leurs générateurs (tools/map_gen/generate_*.gd) pour que portails et arrivées concordent.
##
##                         Gludio Castle
##                               |
##   Orée de la forêt -- Ruins of Agony -- Town of Gludio -- Cruma Marshlands
##                                             |                    |
##                                     Ruins of Despair ------ Town of Dion -- Chemin du cimetière
##
## Comme sur la carte de Lineage 2 : le château juste au nord de la ville, enserré par deux
## bras de rivière ; les ruines d'Agonie à l'ouest, du Désespoir au sud ; les marais de Cruma
## à l'est, au-delà de la rivière qui longe Gludio puis descend vers Dion, au sud-est. L'Orée
## de la forêt et le Chemin du cimetière (anciennes zones, avec leurs monstres) restent
## raccordés au bout des ruines d'Agonie et de Dion.
##
## Positions en cases (1 case = 1 m) ; un portail mène SUR le portail de retour de la carte
## cible.

const GLUDIO_ID := "5e4ada37-37e1-438c-9233-581f10c055c7"
const CASTLE_ID := "82fc00f2-1618-4a94-9e5d-37153ee7e04e"
const AGONY_ID := "9793019d-1705-4d11-a6b4-bcadd8839851"
const DESPAIR_ID := "690d064c-cc26-43df-b8a4-09e41e9e47f8"
const CRUMA_ID := "1505f514-7092-41bb-80e7-2f7bed80b92f"
const DION_ID := "c4177240-7394-4cc5-979f-e0575e6eb6a8"
const OREE_ID := "9a884ac7-b954-4cd6-ab67-c677d472cb0f"
const CEMETERY_PATH_ID := "4dae9974-45f7-46c9-8e66-12cdac759860"

const GLUDIO := "Town of Gludio"
const CASTLE := "Gludio Castle"
const AGONY := "Ruins of Agony"
const DESPAIR := "Ruins of Despair"
const CRUMA := "Cruma Marshlands"
const DION := "Town of Dion"
const OREE := "Orée de la forêt"
const CEMETERY_PATH := "Chemin du cimetière"

const GLUDIO_SIZE := Vector2i(220, 180)
const GLUDIO_PORTAL_N := Vector2(100.5, 5.5)
const GLUDIO_PORTAL_W := Vector2(5.5, 92.5)
const GLUDIO_PORTAL_S := Vector2(100.5, 174.5)
const GLUDIO_PORTAL_E := Vector2(214.5, 92.5)

const CASTLE_SIZE := Vector2i(240, 220)
const CASTLE_PORTAL_S := Vector2(120.5, 214.5)

const AGONY_SIZE := Vector2i(260, 200)
const AGONY_PORTAL_E := Vector2(254.5, 100.5)
const AGONY_PORTAL_W := Vector2(5.5, 100.5)

const DESPAIR_SIZE := Vector2i(240, 220)
const DESPAIR_PORTAL_N := Vector2(120.5, 5.5)
const DESPAIR_PORTAL_E := Vector2(234.5, 150.5)

const CRUMA_SIZE := Vector2i(300, 240)
const CRUMA_PORTAL_W := Vector2(5.5, 120.5)
const CRUMA_PORTAL_S := Vector2(200.5, 234.5)

const DION_SIZE := Vector2i(170, 140)
const DION_PORTAL_N := Vector2(85.5, 5.5)
const DION_PORTAL_W := Vector2(5.5, 70.5)
const DION_PORTAL_E := Vector2(164.5, 70.5)

## Portails des anciennes zones (voir leurs scènes) : est de l'Orée, ouest du Chemin du
## cimetière.
const OREE_PORTAL_E := Vector2(442.0, 135.0)
const CEMETERY_PATH_PORTAL_W := Vector2(6.0, 18.0)
