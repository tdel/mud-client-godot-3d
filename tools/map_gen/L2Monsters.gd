extends RefCounted
## Généré par tools/monster_gen/build_monsters.py : nom de monstre L2 -> templateId serveur
## (backend data/monsters.xml), pour les zones de chasse des générateurs de cartes
## (MapGenBase._monster_zone). Ne pas éditer à la main.

const IDS := {
	"Elder Keltir": "a5d41623-ef47-595b-9907-2e1f95f74f5e",
	"Wolf": "07b2080c-005f-5f49-8f75-7a91217779d4",
	"Elder Wolf": "a24a1968-4d75-5194-901a-80868655a1f4",
	"Giant Toad": "917b0780-9d63-5e51-861e-138e69e79dc1",
	"Goblin": "edc65f4f-c5aa-5683-9367-5b9a8ec421ff",
	"Orc": "9e29e62f-8c6f-5979-9d61-e68657938fa3",
	"Orc Grunt": "f9502f1e-9c06-589e-818d-ea26f6dd15ee",
	"Orc Archer": "c4f9b1f2-3d2f-50f9-99bb-eb161585bf17",
	"Goblin Scout": "8f2fd6d8-3613-5cce-9f77-4143b783443f",
	"Werewolf": "23bc72d4-52a9-50f5-a9e5-21c3418dfeca",
	"Orc Fighter": "d87dc4f2-6e67-56bb-9840-1eeefa6a21c3",
	"Werewolf Hunter": "bef4ed13-2690-5fee-9378-451ed1f59a8f",
	"Vuku Orc": "b8c1bc45-c1fd-54ad-bd86-3c845a624e34",
	"Vuku Orc Archer": "5d3132d0-3ffa-5732-b9ed-bc12f2875b6b",
	"Shadow Beast": "f461a7f4-767f-5852-8ba0-ef11f044b5e7",
	"Ruin Zombie": "53a8f8d2-a4b5-51bb-aca5-ecb9398e16f6",
	"Ruin Zombie Leader": "53814b51-10e4-5982-986b-3377393d15d1",
	"Skeleton Tracker": "6ed54746-6621-5428-84b8-79647d41b0bc",
	"Skeleton Tracker Leader": "65541341-c485-525c-8169-254cb9be7d32",
	"Skeleton Scout": "6801c518-7d10-5807-9fab-2b40686fb61f",
	"Skeleton Bowman": "7bf4ebdd-7408-5fc1-b887-36d875046f43",
	"Ruin Spartoi": "73968160-5efb-5f74-b5dd-dc089a6de8ad",
	"Raging Spartoi": "215fa1ad-e3cb-54dc-a16a-f0b3201b5c4a",
	"Tumran Bugbear Warrior": "b9286bb9-7b27-5cde-bab3-ff4d71c24bff",
	"Soul Scavenger": "d330c90e-943f-5e96-8fd9-2602887c70ea",
	"Shield Skeleton": "fad45921-b52b-5742-b59e-5992dd430030",
	"Skeleton Infantryman": "3d884f61-5374-542f-93e0-630a9d9e0667",
	"Ruin Imp": "de809447-0f18-515c-87a0-b53109c7b749",
	"Scavenger Bat": "5f0ee501-903d-5469-9d21-3b1ac12918ab",
	"Zombie Soldier": "8271cbcb-212b-53ee-84de-6b8efc879ea1",
	"Ruin Bat": "54d7d93c-438f-55d6-a6e4-75f081821535",
	"Ruin Imp Elder": "11243475-243b-5cb2-9a16-6a17f8cdefd3",
	"Zombie Warrior": "b09908f3-6346-5cee-af52-467a9ad455e9",
	"Veelan Bugbear": "1b471703-1e6c-52a2-b22f-709ed9ea9033",
	"Veelan Bugbear Warrior": "dbceafd4-03fe-524c-b160-e3cd999f6022",
	"Zombie Lord Crowl": "452f7ab0-7715-50b2-b39c-ad80af7d3ad7",
	"Giant Mist Leech": "604a0517-20b8-5c98-9f97-798eb49e7826",
	"Gray Ant": "af21daea-e695-5006-b64d-de1b34d57f1f",
	"Horror Mist Ripper": "b975cfc3-f4a4-58d5-83a4-48504ec57715",
	"Giant Crimson Ant": "f0c0c125-7a93-588f-bd7c-d48884b9b3a2",
	"Marsh Stakato": "09941f01-9b22-5c0c-9443-157318319382",
	"Stinger Wasp": "67211bd0-25ff-55fc-b20a-4236119d0c10",
	"Marsh Stakato Worker": "26d564e5-5191-5ce1-bb8a-125755000940",
	"Toad Lord": "52f5142a-d107-5abe-bf9f-423f93df3bd1",
	"Marsh Stakato Soldier": "73cff337-3159-5f55-b51a-7f0c5242512c",
	"Marsh Spider": "4dee2069-5773-5a38-8aa2-6c2aee81c11d",
	"Marsh Stakato Drone": "d39ecf0a-1579-5138-80f3-5845ae45aff4",
	"Stakato Queen Zyrnna": "d6cc26ce-08cc-52ea-af82-462d09635a24",
	"Maille Lizardman": "017a86a7-b167-5f63-832e-2c8bc1bfd60a",
	"Maille Lizardman Scout": "3bdc2d3d-e723-5696-8c86-643e4e6921a4",
	"Maille Lizardman Guard": "ea1d0442-15ea-5102-bdcd-601edf5939ca",
	"Giant Araneid": "470b821d-20ee-5da0-9999-de75a9610b43",
	"Poison Araneid": "1a89f9fb-4795-5a6f-8c04-f1406f784d28",
	"Maille Lizardman Warrior": "0aebd7d2-ab8e-5d92-bb18-8d2a4d892a45",
	"King of the Araneid": "a27792ad-736b-52f5-b97b-fa254db9b3c5",
	"Maille Lizardman Shaman": "e7ebc4d6-eb09-5c3a-9363-c29742f541b3",
	"Maille Lizardman Matriarch": "c474826f-4440-58f1-aeb1-e1dd9a66a9e0",
	"Ratman Spy": "b4059949-d39a-5e50-8eb9-0fdada3095e1",
	"Pinrul": "0312364c-5b30-5367-840f-405cf2d3fcba",
	"Bugbear Raider": "febebf61-a51e-53a4-9db0-6b4070a8e52c",
	"Ratman Hunter": "ae47b62a-16af-597e-a9db-0bb4ee5c62ad",
	"Ratman Sub Chieftain": "ba868ae6-1f94-5d61-8f05-987047b92783",
	"Ratman Chieftain": "dddb1094-eece-5d20-af65-8253da94cfe7",
	"Sukar Wererat Chief": "24f68ef9-2c4a-5611-bf7d-309716445593",
	# Fiches historiques (monstres de départ).
	"Gremlin": "dc803de5-e456-4e20-bbdc-ad16faf99af9",
	"Young Keltir": "8d3b7335-abf5-420e-abf7-3de4160f95ac",
	"Elpy": "e8553837-b812-4826-8740-72df0d9280fd",
	"Fox": "0a88e27c-5487-40d5-b494-b7ea49148171",
	"Brown Keltir": "de87e00a-eb3f-4885-b6a4-922c426d5fb8",
}

## Boss de raid : un seul point, réapparition longue.
const RAID_BOSSES := ["Soul Scavenger", "Zombie Lord Crowl", "Stakato Queen Zyrnna", "Sukar Wererat Chief"]


## [[templateId, poids], ...] pour _monster_zone, depuis [[nom, poids], ...].
static func mix(entries: Array) -> Array:
	var result := []
	for e in entries:
		result.append([IDS[e[0]], e[1]])
	return result
