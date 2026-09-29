@tool
extends RefCounted
## Localisation de l'Asset Drawer.
## Les textes du code sont écrits en français (clé). Si la langue de l'éditeur Godot est le
## français, ils sont affichés tels quels ; sinon la traduction anglaise ci-dessous est utilisée
## (et, à défaut de traduction, le texte d'origine). La langue est lue une fois par session :
## changer la langue de l'éditeur demande de toute façon de le redémarrer.

const EN := {
	"Échec du déplacement": "Move failed",
	"%d élément(s) déplacé(s)": "%d item(s) moved",
	"Élément déplacé": "Item moved",
	"Dossiers": "Folders",
	"Favoris": "Favorites",
	"Récents": "Recents",
	"Tout replier": "Collapse all",
	"Localiser le dossier courant": "Locate current folder",
	"+ Nouveau set": "+ New set",
	"Nouveau set": "New set",
	"mon_set": "my_set",
	"Aucun asset": "No assets",
	"Créer un dossier": "Create a folder",
	"Réinitialiser les filtres": "Reset filters",
	"Coller": "Paste",
	"Coller la ressource copiée ici": "Paste the copied resource here",
	"Copier": "Copy",
	"Copier la ressource": "Copy resource",
	"Ctrl+Espace": "Ctrl+Space",
	"Précédent (bouton souris 4)": "Back (mouse button 4)",
	"Suivant (bouton souris 5)": "Forward (mouse button 5)",
	"Dossier parent (Retour arrière)": "Parent folder (Backspace)",
	"Rechercher... (Ctrl+F)": "Search... (Ctrl+F)",
	"Grille": "Grid",
	"Vue grille": "Grid view",
	"Liste": "List",
	"Vue liste": "List view",
	"Taille des miniatures (Ctrl+molette)": "Thumbnail size (Ctrl+wheel)",
	"Détails": "Details",
	"Panneau de détails": "Details panel",
	"Épingler": "Pin",
	"Épingler (reste ouvert)": "Pin (stays open)",
	"Afficher ce dossier dans le dock Fichiers": "Show this folder in the FileSystem dock",
	"Fermer (Échap)": "Close (Esc)",
	"Tout": "All",
	"Scènes": "Scenes",
	"Modèles": "Models",
	"Taille": "Size",
	"Modifié": "Modified",
	"Ouvrir": "Open",
	"Puis survolez un champ ressource de l'Inspecteur (ex. Mesh d'un MeshInstance3D) : un bouton « Coller » apparaît (ou Alt+V au clavier)": "Then hover a resource field in the Inspector (e.g. the Mesh of a MeshInstance3D): a “Paste” button appears (or press Alt+V)",
	"Coller la ressource": "Paste resource",
	"Copier le chemin": "Copy path",
	"Chemin copié": "Path copied",
	"Ajouter aux favoris": "Add to favorites",
	"Retiré des favoris": "Removed from favorites",
	"Ajouté aux favoris": "Added to favorites",
	"+Dossier": "+Folder",
	"Nouveau dossier": "New folder",
	"+Scène": "+Scene",
	"Clic droit : supprimer le set": "Right-click: delete set",
	"\nClic droit : retirer": "\nRight-click: remove",
	"Supprimer le set": "Delete set",
	"Supprimer le set « %s » ? (les fichiers ne sont pas touchés)": "Delete set “%s”? (files are not touched)",
	"Aucun résultat avec ce filtre": "No results with this filter",
	"Set vide": "Empty set",
	"Aucun résultat": "No results",
	"Taille des icônes en liste (Ctrl+molette)": "Icon size in list view (Ctrl+wheel)",
	"Taille des miniatures en grille (Ctrl+molette)": "Thumbnail size in grid view (Ctrl+wheel)",
	"%d éléments sélectionnés": "%d items selected",
	"Set : ": "Set: ",
	"%d élément%s": "%d item%s",
	" (limité à %d)": " (limited to %d)",
	"à l'instant": "just now",
	"il y a %d min": "%d min ago",
	"il y a %d h": "%d h ago",
	"hier": "yesterday",
	"Dossier": "Folder",
	"%d o": "%d B",
	"%.1f Ko": "%.1f KB",
	"%.1f Mo": "%.1f MB",
	"Retirer des favoris": "Remove from favorites",
	"Cliquer pour ouvrir le tiroir d'assets": "Click to open the asset drawer",
	"Impossible de copier un dossier comme ressource": "Can't copy a folder as a resource",
	"Ce fichier n'est pas une ressource Godot": "This file is not a Godot resource",
	"Impossible de charger la ressource": "Can't load the resource",
	"« %s » copiée — survolez un champ ressource de l'Inspecteur": "“%s” copied — hover a resource field in the Inspector",
	"Aucune ressource copiée : clic droit sur un fichier → « Copier la ressource »": "No resource copied: right-click a file → “Copy resource”",
	"Survolez un champ ressource de l'Inspecteur puis Alt+V": "Hover a resource field in the Inspector, then press Alt+V",
	"Ce champ n'est pas modifiable": "This field is read-only",
	"Type incompatible : ce champ attend « %s »": "Incompatible type: this field expects “%s”",
	"« %s » collée dans l'Inspecteur": "“%s” pasted into the Inspector",
	"COULEUR DU DOSSIER": "FOLDER COLOR",
	"Couleur par défaut": "Default color",
	"Afficher dans le dock Fichiers": "Show in FileSystem dock",
	"Afficher dans l'explorateur": "Show in file manager",
	"Copier le chemin absolu": "Copy absolute path",
	"Chemin absolu copié": "Absolute path copied",
	"Copier la ressource   (bouton Coller au survol)": "Copy resource   (Paste button on hover)",
	"Copier l'UID": "Copy UID",
	"UID copié": "UID copied",
	"Ouvrir le dossier dans l'explorateur": "Open folder in file manager",
	"Copier le chemin du dossier": "Copy folder path",
	"Copier le chemin absolu du dossier": "Copy folder absolute path",
	"Retirer le dossier des favoris": "Remove folder from favorites",
	"Ajouter le dossier aux favoris": "Add folder to favorites",
	"Actualiser": "Refresh",
	"Actualisé": "Refreshed",
	"Passer en vue grille": "Switch to grid view",
	"Passer en vue liste": "Switch to list view",
	"Nouvelle scène": "New scene",
	"Nouveau script": "New script",
	"Renommer (F2)": "Rename (F2)",
	"Dupliquer (Ctrl+D)": "Duplicate (Ctrl+D)",
	"Ajouter à un set...": "Add to a set...",
	"Ajouter au set": "Add to set",
	"Ajouté au set « %s »": "Added to set “%s”",
	"Retirer de ce set": "Remove from this set",
	"Réimporter": "Reimport",
	"Supprimer (Suppr)": "Delete (Del)",
	"Nom invalide : caractère « %s » interdit": "Invalid name: character “%s” not allowed",
	"nouveau_dossier": "new_folder",
	"« %s » existe déjà": "“%s” already exists",
	"nouvelle_scene": "new_scene",
	"nouveau_script": "new_script",
	"Renommer": "Rename",
	"Échec du renommage": "Rename failed",
	"Renommé en « %s »": "Renamed to “%s”",
	"_copie": "_copy",
	"%d élément(s) dupliqué(s)": "%d item(s) duplicated",
	"Élément dupliqué": "Item duplicated",
	"Envoyer à la corbeille :\n": "Move to trash:\n",
	"Supprimer": "Delete",
	"Impossible de mettre « %s » à la corbeille": "Can't move “%s” to trash",
	"%d élément(s) envoyé(s) à la corbeille": "%d item(s) moved to trash",
	"Envoyé à la corbeille": "Moved to trash",
	"Valider": "OK",
	"Annuler": "Cancel",
	"Confirmer": "Confirm",
	" · %d sélectionné%s": " · %d selected%s",
	"Asset Drawer (Ctrl+Espace)": "Asset Drawer (Ctrl+Space)",
}

static var _fr := -1


static func is_fr() -> bool:
	if _fr < 0:
		_fr = 1 if _detect_fr() else 0
	return _fr == 1


static func t(fr: String) -> String:
	if is_fr():
		return fr
	return str(EN.get(fr, fr))


## Marque du pluriel "s" (français uniquement) pour les mots comme "sélectionné(s)".
static func sel_s(plural: bool) -> String:
	return "s" if plural and is_fr() else ""


static func _detect_fr() -> bool:
	var loc := ""
	if TranslationServer.has_method("get_tool_locale"):
		loc = str(TranslationServer.call("get_tool_locale"))
	else:
		var lang := str(EditorInterface.get_editor_settings().get_setting("interface/editor/editor_language"))
		loc = OS.get_locale() if lang == "" or lang == "auto" else lang
	return loc.to_lower().begins_with("fr")
