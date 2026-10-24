extends RefCounted
## Géographie commune des cartes des régions de Gludio et de Dion (façon Lineage 2),
## partagée par leurs générateurs (tools/map_gen/generate_*.gd) pour que portails et
## arrivées concordent.
##
##                              Neutral Zone
##                             /           |
##                            /      Gludio Castle
##                           /             |
##   Fellmere Lake -- Ruins of Agony -- Town of Gludio -- Cruma Marshlands
##                                      |          \            |
##                              Ruins of Despair ---- Town of Dion -- Execution Grounds
##                                                         |
##                                                    Dion Castle
##
## Comme sur la carte de Lineage 2 : le château juste au nord de la ville, enserré par deux
## bras de rivière, et la Neutral Zone au-delà, au nord (on y monte du château par le pont
## du bras nord, ou de Gludio par la route qui contourne le château à l'ouest) ; les ruines
## d'Agonie à l'ouest puis le lac de Fellmere ; les ruines du Désespoir au sud ; les marais
## de Cruma à l'est, au-delà de la rivière qui longe Gludio puis descend vers Dion, au
## sud-est (une route directe relie aussi Gludio à Dion) ; les Execution Grounds à l'est de
## Dion, le château de Dion au sud, vers Floran.
##
## Positions en cases (1 case = 1 m) ; un portail mène SUR le portail de retour de la carte
## cible. Place de chaque carte sur la carte du monde (touche M, clic droit) : voir
## MapAtlas.WORLD_ORIGINS, à compléter pour une nouvelle région.

const GLUDIO_ID := "5e4ada37-37e1-438c-9233-581f10c055c7"
const CASTLE_ID := "82fc00f2-1618-4a94-9e5d-37153ee7e04e"
const AGONY_ID := "9793019d-1705-4d11-a6b4-bcadd8839851"
const DESPAIR_ID := "690d064c-cc26-43df-b8a4-09e41e9e47f8"
const CRUMA_ID := "1505f514-7092-41bb-80e7-2f7bed80b92f"
const DION_ID := "c4177240-7394-4cc5-979f-e0575e6eb6a8"
const NEUTRAL_ID := "a00104cf-8e60-4613-91f2-fc29333464b2"
const FELLMERE_ID := "eb42914e-9437-4269-966a-067e30948875"
const EXECUTION_ID := "68f5aa7d-e915-45d8-880a-757726afb1eb"
const DION_CASTLE_ID := "0c08915d-bd51-417d-aa73-c5e3e38ea45e"

const GLUDIO := "Town of Gludio"
const CASTLE := "Gludio Castle"
const AGONY := "Ruins of Agony"
const DESPAIR := "Ruins of Despair"
const CRUMA := "Cruma Marshlands"
const DION := "Town of Dion"
const NEUTRAL := "Neutral Zone"
const FELLMERE := "Fellmere Lake"
const EXECUTION := "Execution Grounds"
const DION_CASTLE := "Dion Castle"

const GLUDIO_SIZE := Vector2i(220, 180)
const GLUDIO_PORTAL_N := Vector2(100.5, 5.5)
const GLUDIO_PORTAL_W := Vector2(5.5, 92.5)
const GLUDIO_PORTAL_S := Vector2(100.5, 174.5)
const GLUDIO_PORTAL_E := Vector2(214.5, 92.5)
## Coin nord-ouest (bord ouest) : la route de la Neutral Zone, qui contourne le château.
const GLUDIO_PORTAL_NW := Vector2(5.5, 12.5)
## Bord sud, à l'est de la route du Désespoir : la route directe de Dion.
const GLUDIO_PORTAL_SE := Vector2(160.5, 174.5)

const CASTLE_SIZE := Vector2i(240, 220)
const CASTLE_PORTAL_S := Vector2(120.5, 214.5)
## Au nord, au-delà du pont jeté sur le bras ouest de la rivière : vers la Neutral Zone.
const CASTLE_PORTAL_N := Vector2(95.5, 5.5)

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
## Bord nord, à l'ouest de la route de Cruma : la route directe de Gludio.
const DION_PORTAL_NW := Vector2(40.5, 5.5)
## Bord sud, au bout de la route de la porte sud : vers le château de Dion.
const DION_PORTAL_S := Vector2(85.5, 134.5)

const NEUTRAL_SIZE := Vector2i(300, 240)
## Deux portails sur le bord sud : à l'ouest vers Gludio, au milieu vers le château.
const NEUTRAL_PORTAL_SW := Vector2(30.5, 234.5)
const NEUTRAL_PORTAL_S := Vector2(195.5, 234.5)

const FELLMERE_SIZE := Vector2i(280, 240)
const FELLMERE_PORTAL_E := Vector2(274.5, 120.5)

const EXECUTION_SIZE := Vector2i(280, 240)
const EXECUTION_PORTAL_W := Vector2(5.5, 120.5)

const DION_CASTLE_SIZE := Vector2i(260, 240)
const DION_CASTLE_PORTAL_N := Vector2(130.5, 5.5)
