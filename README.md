# EasyRaidSaver 1.2
Raid organizer for Weird Vibes of Turtle Wow

Example config:
---
```
Layout Name: Typical Raid

Group 1: Dewbie, Rootankman, Valamas, Ehawne, Clappicus
Group 2: Friendhelper>Shaman, Rinjuli, Khoni, Wynndras, Hoyu
Group 3: Zorizar>Shaman, Liegekiller, Onnix, Hunter>Melee, Melee
Group 4: Shaman>Melee, Spire, Weiss, Hunter>Melee, Melee
Group 5: Shaman>Melee, Hunter>Melee, Melee, Melee, Melee
Group 6: Grueten,Astiel>Mage,Aest>Mage,Pepopo,Scarletrage
Group 7: Iggy,Ferroklast,Neeze,Pookers,Olemossy
Group 8: Warlock,Warlock,Warlock,Itchynuts
windfury: khoni,rinjuli,wynndras,liegekiller,onnix,spire,weiss
healer: Olemossy,iggy,ferroklast,neeze,pookers,friendhelper,ehawne,largetotem
tank: dewbie,rootankman,valamas,ehawne
melee: etc
```

Specifiers:
---
Classes: `Group 3: Zorizar>Shaman, Liegekiller, Onnix, Rogue, Hunter`

Roles: `Group 5: Melee, Spire, Weiss, Melee, Healer`
* `Tank`: warrior,druid,paladin -- This isn't used currently just name your tanks
* `Healer`: shaman,priest,druid,paladin
* `Melee`: rogue,warrior,druid,paladin
* `Range`: hunter,mage,warlock,priest,druid,shaman
* `Decurse`: mage,druid

Prios: `Windfury: Khoni, Rinjuli, Wynndras`
* `Windfury` gives a list of `Melee` name to prio windfury for if a group with a shaman has room.
* `Tank` gives a list of `Tank` names to help the differentiate roles.
* `Melee` gives a list of `Melee` names to help the differentiate roles.
* `Range` gives a list of `Range` names to help the differentiate roles.

___
The addon will attempt to auto-expand names for you when a unique choice exists. So you can write Ferro and it will place Ferroklast in the Ferro slot but only if there isn't also a Ferrobloop in raid.  

If the "Show/Hide the raid Layout Editor" arrow-button is green it means there's an active applied configuration and that auto-apply is also enabled which will re-order the raid any time the roster updates.  

* addon is incomplete, `windfury` doesn't do anything currently for instance

___
* Made by and for Weird Vibes of Turtle Wow  
