Locales = Locales or {}

Locales['fr'] = {
    general = {
        resource = 'Objets plaçables',
        no_model = "Aucun modèle de prop n'est défini pour cet item.",
        invalid_item = "Vous ne pouvez pas placer cet item.",
        place_success = 'Objet posé.',
        remove_success = 'Objet récupéré.',
        removing = 'Suppression de l\'objet...',
        press_collect = 'Appuyez sur ~INPUT_PICKUP~ pour ramasser'
    },
    validation = {
        too_far = "Vous êtes trop loin pour poser cet objet.",
        too_close = "Reculez un peu avant de poser cet objet.",
        stacking = "Impossible de placer des objets aussi proches.",
        trunk_full = 'Ce coffre est plein.',
        trunk_only = 'Cet item doit être rangé dans un coffre.',
        invalid_surface = "Vous ne pouvez pas poser cet objet ici.",
        need_ground = "Visez une surface valide avant de poser."
    },
    placement = {
        prompt = 'Utilisez ~g~%s~s~ pour confirmer, ~r~%s~s~ pour annuler.',
        drop_on = 'Mode lâcher activé (objet dynamique).',
        drop_off = 'Mode lâcher désactivé (objet figé).',
        trunk_slot = 'Emplacement %s/%s'
    },
    target = {
        collect = 'Ramasser',
        inspect = 'Inspecter',
        remove = 'Retirer (staff)'
    },
    inspect = {
        owner = 'Propriétaire : %s',
        item = 'Item : %s'
    },
    commands = {
        missing_item = 'Usage : /place <nom de l\'item>',
        unknown_item = 'Item inconnu.',
        cancelled = 'Placement annulé.',
        cleaned = 'Tous les objets ont été retirés.'
    }
}
