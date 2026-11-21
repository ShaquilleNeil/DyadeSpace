// Hand-rolled EN/FR/ES strings (no code generation needed).
// Add a key here, then use it via `ref.watch(stringsProvider)`.
import '../models/stage.dart';

class AppStrings {
  final String lang; // 'en', 'fr' or 'es'
  const AppStrings(this.lang);

  bool get isFr => lang == 'fr';
  String _t(String en, String fr, String es) =>
      lang == 'fr' ? fr : (lang == 'es' ? es : en);

  String get appTitle => 'DyadeSpace';
  String get signIn => _t('Sign in', 'Se connecter', 'Iniciar sesión');
  String get signOut => _t('Sign out', 'Se déconnecter', 'Cerrar sesión');
  String get themeLight => _t('Light', 'Clair', 'Claro');
  String get themeDark => _t('Dark', 'Sombre', 'Oscuro');
  String get email => _t('Email', 'Courriel', 'Correo');
  String get password => _t('Password', 'Mot de passe', 'Contraseña');
  String get inviteOnly => _t(
      'Accounts are invite-only. Ask Sam or Alex for an invite.',
      'Comptes sur invitation seulement. Demandez une invitation à Sam ou Alex.',
      'Las cuentas son solo por invitación. Pide una invitación a Sam o Alex.');
  String get board => _t('Board', 'Tableau', 'Tablero');
  String get today => _t('Today', "Aujourd'hui", 'Hoy');
  // Board search + filters (the Today tab lives here now, as a filter).
  String get searchTasksHint => _t(
      'Search tasks, sites, people',
      'Rechercher tâches, chantiers, personnes',
      'Buscar tareas, obras, personas');
  String get filterAll => _t('All', 'Toutes', 'Todas');
  String get noTasksMatch => _t('No tasks match.',
      'Aucune tâche ne correspond.', 'Ninguna tarea coincide.');
  String get byPerson => _t('By person', 'Par personne', 'Por persona');
  String get reports => _t('Reports', 'Rapports', 'Informes');
  String get team => _t('Team', 'Équipe', 'Equipo');
  String get myDay => _t('My Day', 'Ma journée', 'Mi día');
  String get history => _t('History', 'Historique', 'Historial');
  String get run => _t('Run', 'Tournée', 'Ruta');
  String get overdue => _t('Overdue', 'En retard', 'Atrasado');
  String get toDo => _t('To do', 'À faire', 'Por hacer');
  String get inProgress => _t('In progress', 'En cours', 'En curso');
  String get blocked => _t('Blocked', 'Bloqué', 'Bloqueado');
  String get toConfirm => _t('To confirm', 'À confirmer', 'Por confirmar');
  String get done => _t('Done', 'Terminé', 'Terminado');
  String get start => _t('Start', 'Commencer', 'Comenzar');
  String get markDone => _t('Done', 'Terminer', 'Terminar');
  String get markBlocked => _t('Blocked', 'Bloqué', 'Bloqueado');
  String get addPhoto => _t('Add photo', 'Ajouter une photo', 'Agregar foto');
  String get photoRequiredNote => _t(
      'A photo is required to mark this done.',
      'Une photo est requise pour marquer terminé.',
      'Se requiere una foto para marcar esto como terminado.');
  String get locked => _t(
      'Locked - waiting on the task before it.',
      'Verrouillé - en attente de la tâche précédente.',
      'Bloqueado: esperando la tarea anterior.');
  String waitingOn(String title) => _t(
      'Waiting on: $title', 'En attente de : $title', 'En espera de: $title');
  String stepOf(int step, int total) => _t(
      'Step $step of $total', 'Étape $step sur $total', 'Paso $step de $total');
  String unlocksNext(String title) => _t('Finishing this unlocks: $title',
      'Terminer ceci débloque : $title', 'Terminar esto desbloquea: $title');
  String get startsOn => _t('Starts', 'Début', 'Comienza');
  String get canStartEarly => _t(
      'Can start before the previous task is done',
      'Peut commencer avant la fin de la tâche précédente',
      'Puede empezar antes de que termine la tarea anterior');
  String usuallyAfter(String title) => _t(
      'Usually after: $title - can start early',
      'Habituellement après : $title - peut commencer tôt',
      'Normalmente después de: $title — puede empezar antes');
  String dayOf(int day, int total) =>
      _t('Day $day of $total', 'Jour $day sur $total', 'Día $day de $total');
  String get carriedOver => _t('Carried over', 'Reportée', 'Trasladada');
  String get pushToTomorrow =>
      _t('Push to tomorrow', 'Repousser à demain', 'Pasar a mañana');
  String get materials =>
      _t('Materials on site', 'Matériaux sur place', 'Materiales en obra');
  String get notes => _t('Notes', 'Notes', 'Notas');
  String get due => _t('Due', 'Échéance', 'Vencimiento');
  String get noTasks => _t('No tasks.', 'Aucune tâche.', 'No hay tareas.');
  String get newTask => _t('New task', 'Nouvelle tâche', 'Nueva tarea');
  String get editTask => _t('Edit task', 'Modifier la tâche', 'Editar tarea');
  String get edit => _t('Edit', 'Modifier', 'Editar');
  String get taskNeedsTitle => _t(
      'Give the task a title first.',
      'Donnez d’abord un titre à la tâche.',
      'Ponle un título a la tarea primero.');
  String get taskNeedsSite => _t(
      'Pick a site first — a task has to belong to a site.',
      'Choisissez d’abord un chantier — une tâche doit appartenir à un chantier.',
      'Elige primero una obra: cada tarea pertenece a una obra.');
  String taskSaveFailed(String error) => _t(
      'Could not save the task: $error',
      'Impossible d’enregistrer la tâche : $error',
      'No se pudo guardar la tarea: $error');
  String get title => _t('Title', 'Titre', 'Título');
  String get site => _t('Site', 'Chantier', 'Obra');
  String get unit => _t('Unit', 'Unité', 'Unidad');
  String get assignee => _t('Assigned to', 'Assigné à', 'Asignada a');
  String get searchPeopleHint => _t(
      'Search people', 'Rechercher des personnes', 'Buscar personas');
  String get noPeopleMatch => _t(
      'No one matches.', 'Personne ne correspond.', 'Nadie coincide.');
  String get save => _t('Save', 'Enregistrer', 'Guardar');
  String get invite => _t('Invite', 'Inviter', 'Invitar');
  String get generateReport => _t('Generate today\'s report',
      'Générer le rapport du jour', 'Generar el informe de hoy');
  String get pickedUp =>
      _t('Mark picked up', 'Marquer ramassé', 'Marcar como recogido');
  String get delivered =>
      _t('Mark delivered', 'Marquer livré', 'Marcar como entregado');
  String get nextStop => _t('Next stop', 'Prochain arrêt', 'Próxima parada');
  String get blockedReason => _t('Why is it blocked?',
      'Pourquoi est-ce bloqué ?', '¿Por qué está bloqueada?');
  String get waitingMaterials => _t('Waiting on materials',
      'En attente de matériaux', 'Esperando materiales');
  String get waitingPerson => _t('Waiting on another person',
      'En attente d\'une autre personne', 'Esperando a otra persona');
  String get noAccess => _t('No access', 'Pas d\'accès', 'Sin acceso');
  String get other => _t('Other', 'Autre', 'Otro');
  String get cancel => _t('Cancel', 'Annuler', 'Cancelar');
  String get confirm => _t('Confirm', 'Confirmer', 'Confirmar');
  String get discard => _t('Discard', 'Abandonner', 'Descartar');
  String get discardChanges => _t('Discard changes?',
      'Abandonner les modifications ?', '¿Descartar los cambios?');
  String get discardChangesConfirm => _t(
      'Your unsaved edits will be lost.',
      'Vos modifications non enregistrées seront perdues.',
      'Se perderán los cambios sin guardar.');

  // --- Delivery runs: builder (manager) ---
  String get planRun => _t('Plan a delivery run', 'Planifier une tournée',
      'Planificar una ruta de entrega');
  String get date => _t('Date', 'Date', 'Fecha');
  String get driver => _t('Driver', 'Chauffeur', 'Conductor');
  String get addStop => _t('Add stop', 'Ajouter un arrêt', 'Agregar parada');
  String stopNumber(int n) => _t('Stop $n', 'Arrêt $n', 'Parada $n');
  String get address => _t('Address', 'Adresse', 'Dirección');
  String get pickup => _t('Pickup', 'Ramassage', 'Recogida');
  String get dropoff => _t('Drop-off', 'Livraison', 'Entrega');
  String get stopKind => _t('Stop type', 'Type d’arrêt', 'Tipo de parada');
  String get beThereBy => _t('Be there by', 'Sur place à', 'Estar allí a las');
  String get itemsOnePerLine => _t('Items (one per line)',
      'Articles (un par ligne)', 'Artículos (uno por línea)');
  String get linkedTask => _t('Linked task', 'Tâche liée', 'Tarea vinculada');
  String get noneOption => _t('None', 'Aucun', 'Ninguno');
  String get moveUp => _t('Move up', 'Monter', 'Subir');
  String get moveDown => _t('Move down', 'Descendre', 'Bajar');
  String get removeStop =>
      _t('Remove stop', 'Retirer l’arrêt', 'Quitar parada');
  String get pickDriverFirst => _t('Pick a driver first.',
      'Choisissez d’abord un chauffeur.', 'Elige primero un conductor.');
  String get runNeedsStop => _t(
      'Add at least one stop first.',
      'Ajoutez d’abord au moins un arrêt.',
      'Agrega al menos una parada primero.');
  String get stopNeedsTitle => _t(
      'Give every stop a title first.',
      'Donnez d’abord un titre à chaque arrêt.',
      'Ponle primero un título a cada parada.');
  String get runSaved =>
      _t('Run saved.', 'Tournée enregistrée.', 'Ruta guardada.');
  String runSaveFailed(String error) => _t(
      'Could not save the run: $error',
      'Impossible d’enregistrer la tournée : $error',
      'No se pudo guardar la ruta: $error');
  String get editRun => _t('Edit run', 'Modifier la tournée', 'Editar ruta');
  String get runExistsTitle =>
      _t('Run already exists', 'Tournée déjà existante', 'Ya existe una ruta');
  String runExistsMessage(String driver, int count) => _t(
      '$driver already has a run this day with $count stops.',
      '$driver a déjà une tournée ce jour-là avec $count arrêts.',
      '$driver ya tiene una ruta este día con $count paradas.');
  String get openExistingRun => _t('Open the existing run',
      'Ouvrir la tournée existante', 'Abrir la ruta existente');
  String get createSecondRun => _t('Create a second run',
      'Créer une deuxième tournée', 'Crear una segunda ruta');

  // --- Delivery runs: driver screen ---
  String get couldNotComplete =>
      _t("Couldn't complete", 'Impossible de terminer', "No se pudo completar");
  String get whyNotComplete =>
      _t('What happened?', 'Que s’est-il passé ?', '¿Qué pasó?');
  String get failedStop => _t('Not completed', 'Non complété', 'Sin completar');
  String get failOutOfStock =>
      _t('Out of stock', 'Rupture de stock', 'Sin existencias');
  String get failWrongItem =>
      _t('Wrong item', 'Mauvais article', 'Artículo equivocado');
  String get failNobodyThere =>
      _t('Nobody there', 'Personne sur place', 'Nadie en el lugar');
  String stopsDone(int done, int total) => _t(
      '$done of $total stops done',
      '$done arrêts sur $total terminés',
      '$done de $total paradas completadas');
  String stopsFailed(int n) =>
      _t('$n not completed', '$n non complété(s)', '$n sin completar');
  String get runFinishedIssues => _t('Run finished - with issues',
      'Tournée terminée - avec des problèmes', 'Ruta terminada, con problemas');
  String get checkItemsHint => _t(
      'Check each item as you load it',
      'Cochez chaque article en le chargeant',
      'Marca cada artículo al cargarlo');
  String get directions => _t('Directions', 'Itinéraire', 'Indicaciones');
  String get startRoute =>
      _t('Start route', 'Lancer l’itinéraire', 'Iniciar ruta');

  // --- Delivery runs: manager progress view ---
  String get runProgress =>
      _t('Run progress', 'Suivi des tournées', 'Seguimiento de rutas');
  String get noRunsForDay => _t('No runs for this day.',
      'Aucune tournée pour cette journée.', 'No hay rutas para este día.');

  // --- Tasks: delivery confirmation ---
  String get materialsOnSite =>
      _t('Materials on site', 'Matériaux sur place', 'Materiales en obra');

  // --- Sites: management screen (manager) ---
  String get sites => _t('Sites', 'Chantiers', 'Obras');
  String get addSite => _t('Add site', 'Ajouter un chantier', 'Agregar obra');
  String get editSite => _t('Edit site', 'Modifier le chantier', 'Editar obra');
  String get name => _t('Name', 'Nom', 'Nombre');
  String get delete => _t('Delete', 'Supprimer', 'Eliminar');
  String deleteSiteConfirm(String siteName) => _t(
      'Delete $siteName? This cannot be undone.',
      'Supprimer $siteName ? Cette action est irréversible.',
      '¿Eliminar $siteName? Esto no se puede deshacer.');
  String get siteHasTasks => _t(
      'This site still has tasks - move or delete them first.',
      'Ce chantier a encore des tâches - déplacez-les ou supprimez-les d’abord.',
      'Esta obra aún tiene tareas: muévelas o elimínalas primero.');
  String get siteSaved =>
      _t('Site saved.', 'Chantier enregistré.', 'Obra guardada.');
  String siteSaveFailed(String error) => _t(
      'Could not save the site: $error',
      'Impossible d’enregistrer le chantier : $error',
      'No se pudo guardar la obra: $error');
  String get siteDeleted =>
      _t('Site deleted.', 'Chantier supprimé.', 'Obra eliminada.');
  String get siteNeedsName => _t(
      'Give the site a name first.',
      'Donnez d’abord un nom au chantier.',
      'Ponle primero un nombre a la obra.');
  String get noSites => _t(
      'No sites yet.', 'Aucun chantier pour le moment.', 'Aún no hay obras.');
  String get noRoadmap =>
      _t('No roadmap', 'Aucune feuille de route', 'Sin hoja de ruta');

  // --- Delivery runs: materials-blocked suggestions (builder) ---
  String get materialsSuggestions => _t(
      'Blocked on materials - suggested pickups',
      'Bloquées faute de matériaux - ramassages suggérés',
      'Bloqueadas por falta de materiales: recogidas sugeridas');
  String get addPickupStop => _t('Add pickup stop',
      'Ajouter un arrêt de ramassage', 'Agregar parada de recogida');
  String materialsFor(String title) => _t('Materials for $title',
      'Matériaux pour $title', 'Materiales para $title');

  // --- Reports: share progress (client update) ---
  String get shareProgress =>
      _t('Share progress', 'Partager l’avancement', 'Compartir avance');
  String get progressUpdate => _t('Progress update',
      'Mise à jour de l’avancement', 'Actualización de avance');
  String get pickSite =>
      _t('Pick a site', 'Choisir un chantier', 'Elige una obra');
  String get noWorkYet => _t(
      'No work to report yet.',
      'Aucun travail à signaler pour le moment.',
      'Aún no hay trabajo que reportar.');
  String get copy => _t('Copy', 'Copier', 'Copiar');
  String get copied => _t('Copied to clipboard.',
      'Copié dans le presse-papiers.', 'Copiado al portapapeles.');
  String get share => _t('Share', 'Partager', 'Compartir');

  // --- Client share link: a public, read-only progress view
  // per site, opened from a link with no app or login. ---
  String get shareWithClient =>
      _t('Share with client', 'Partager avec le client', 'Compartir con el cliente');
  String get clientShareTitle =>
      _t('Client link', 'Lien client', 'Enlace para el cliente');
  String get clientShareIntro => _t(
      'Anyone with this link can see this site’s progress. No app or login needed.',
      'Toute personne avec ce lien peut voir l’avancement de ce chantier. Aucune application ni connexion requise.',
      'Cualquier persona con este enlace puede ver el avance de esta obra. No necesita aplicación ni inicio de sesión.');
  String get clientShareCopyLink =>
      _t('Copy client link', 'Copier le lien client', 'Copiar enlace para el cliente');
  String get clientShareLinkCopied => _t('Client link copied.',
      'Lien client copié.', 'Enlace para el cliente copiado.');
  String get clientShareLinkCreated => _t('Client link created.',
      'Lien client créé.', 'Enlace para el cliente creado.');
  String get clientShareRevoke =>
      _t('Revoke link', 'Révoquer le lien', 'Revocar enlace');
  String get clientShareLinkRevoked => _t('Client link revoked.',
      'Lien client révoqué.', 'Enlace para el cliente revocado.');
  String get clientShareRegenerate =>
      _t('New link', 'Nouveau lien', 'Nuevo enlace');
  String get clientShareLinkRegenerated => _t(
      'Old link revoked, new link created.',
      'Ancien lien révoqué, nouveau lien créé.',
      'Enlace anterior revocado, nuevo enlace creado.');
  String get clientShareInvalid => _t(
      'This link is not valid, or it was revoked.',
      'Ce lien n’est pas valide ou il a été révoqué.',
      'Este enlace no es válido o fue revocado.');
  String get clientShareLoadFailed => _t(
      'Could not load this site’s progress. Try again later.',
      'Impossible de charger l’avancement de ce chantier. Réessayez plus tard.',
      'No se pudo cargar el avance de esta obra. Inténtalo más tarde.');
  String get clientShareRecentWork =>
      _t('Recently completed', 'Récemment terminé', 'Completado recientemente');
  String get clientShareNoProgress => _t(
      'No work reported yet for this site.',
      'Aucun travail signalé pour ce chantier.',
      'Aún no hay trabajo reportado para esta obra.');
  String get clientShareNoLinkYet => _t(
      'No client link yet for this site.',
      'Aucun lien client pour ce chantier.',
      'Aún no hay enlace para el cliente para esta obra.');
  String get clientShareFooter => _t(
      'Shared from DyadeSpace — a read-only view, no sign-in needed.',
      'Partagé depuis DyadeSpace — vue en lecture seule, aucune connexion requise.',
      'Compartido desde DyadeSpace: vista de solo lectura, sin inicio de sesión.');
  String get inviteAdminRequiresAdmin => _t(
      'Only an admin can invite an admin.',
      'Seul un administrateur peut inviter un administrateur.',
      'Solo un administrador puede invitar a un administrador.');
  String get runStopCompleted =>
      _t('Stop completed.', 'Arrêt terminé.', 'Parada completada.');
  String get runStopFailed => _t('Stop marked as not completed.',
      'Arrêt marqué non complété.', 'Parada marcada como sin completar.');
  String get runStopPhotoHint => _t(
      'A photo is appreciated but not required to finish the stop.',
      'Une photo est appréciée, mais pas obligatoire pour terminer l’arrêt.',
      'Se agradece una foto, pero no es obligatoria para terminar la parada.');
  String get runStopCompleteWithoutPhoto => _t(
      'Complete without photo',
      'Terminer sans photo',
      'Completar sin foto');
  String get runStopAddPhotoAndComplete => _t(
      'Add photo and complete',
      'Ajouter une photo et terminer',
      'Agregar foto y completar');

  // --- Reports: end-of-day check ---
  String get todaysSnapshot =>
      _t("Today's snapshot", 'Aperçu du jour', "Resumen del día");
  String get photoProof => _t('Photo proof — today',
      'Preuves photo — aujourd’hui', 'Prueba fotográfica: hoy');
  String get thisWeek => _t('This week', 'Cette semaine', 'Esta semana');
  String get whoDidWhat =>
      _t('Who did what', 'Qui a fait quoi', 'Quién hizo qué');
  String get sendReport => _t(
      'Send end-of-day report',
      'Envoyer le rapport de fin de journée',
      'Enviar el informe de fin de día');
  String get sendNow => _t('Send now', 'Envoyer maintenant', 'Enviar ahora');
  String get sendChannel => _t('Send by', 'Envoyer par', 'Enviar por');
  String get channelPush => _t('Push', 'Push', 'Push');
  String get channelEmail => _t('Email', 'Courriel', 'Correo');
  String get channelBoth => _t('Both', 'Les deux', 'Ambos');
  String get reportSendRequested => _t('Report send requested.',
      'Envoi du rapport demandé.', 'Envío del informe solicitado.');
  String get reportSendFailed => _t(
      'Could not request the report send.',
      'Impossible de demander l’envoi du rapport.',
      'No se pudo solicitar el envío del informe.');
  String get noBlockedTasks =>
      _t('Nothing blocked.', 'Rien de bloqué.', 'Nada bloqueado.');
  String get noPhotosToday => _t(
      'No completion photos today yet.',
      'Aucune photo de tâche terminée aujourd’hui pour le moment.',
      'Aún no hay fotos de tareas terminadas hoy.');
  String get noWorkThisWeek => _t(
      'No work finished this week yet.',
      'Aucun travail terminé cette semaine pour le moment.',
      'Aún no hay trabajo terminado esta semana.');
  String get pastReports =>
      _t('Past reports', 'Rapports précédents', 'Informes anteriores');

  // --- Team: pending invites + invite email ---
  String get pendingInvites => _t(
      'Pending invites', 'Invitations en attente', 'Invitaciones pendientes');
  String get sendInviteEmail => _t('Send invite email',
      'Envoyer l’invitation par courriel', 'Enviar la invitación por correo');
  String get inviteEmailSubject => _t('You\'re invited to DyadeSpace',
      'Vous êtes invité à DyadeSpace', 'Te invitamos a DyadeSpace');
  String inviteEmailBody(String email, String role) => _t(
      'You\'ve been invited to join DyadeSpace, the crew app for Dyade Management.\n\n'
          'Install the app, then sign up using exactly this email address: $email\n'
          'Your role will be: $role\n\n'
          'If you need the download link, just reply to this email.',
      'Vous êtes invité à rejoindre DyadeSpace, l’application d’équipe de Dyade Management.\n\n'
          'Installez l’application, puis inscrivez-vous en utilisant exactement cette adresse courriel : $email\n'
          'Votre rôle sera : $role\n\n'
          'Si vous avez besoin du lien de téléchargement, répondez simplement à ce courriel.',
      'Te invitamos a unirte a DyadeSpace, la app del equipo de Dyade Management.\n\n'
          'Instala la app y regístrate usando exactamente esta dirección de correo: $email\n'
          'Tu rol será: $role\n\n'
          'Si necesitas el enlace de descarga, responde a este correo.');
  String get noMailApp => _t(
      'No mail app found on this device.',
      'Aucune application de courriel trouvée sur cet appareil.',
      'No se encontró ninguna app de correo en este dispositivo.');

  // --- Tasks: updates thread (detail screen) ---
  String get updates => _t('Updates', 'Mises à jour', 'Actualizaciones');
  String get addAnUpdate => _t(
      'Add an update', 'Ajouter une mise à jour', 'Agregar una actualización');
  String get post => _t('Post', 'Publier', 'Publicar');
  String get noUpdatesYet => _t('No updates yet.',
      'Aucune mise à jour pour le moment.', 'Aún no hay actualizaciones.');
  String get updateNeedsContent => _t(
      'Write something or add a photo first.',
      'Écrivez quelque chose ou ajoutez d’abord une photo.',
      'Escribe algo o agrega primero una foto.');
  String updatePostFailed(String error) => _t(
      'Could not post the update: $error',
      'Impossible de publier la mise à jour : $error',
      'No se pudo publicar la actualización: $error');
  String get updateSending => _t('Sending…', 'Envoi en cours…', 'Enviando…');
  String get updateWaitingForConnection => _t(
      'Will send when you\'re back online',
      'Sera envoyé dès le retour du réseau',
      'Se enviará cuando vuelvas a tener conexión');
  String get photoUploadFailed => _t(
      'Photo upload failed - check your connection and try again.',
      'Échec de l’envoi de la photo - vérifiez votre connexion et réessayez.',
      'No se pudo enviar la foto: revisa tu conexión e inténtalo de nuevo.');

  // --- Photos: offline queue ---
  String get photoQueuedOffline => _t(
      'No connection - this photo will send itself when you\'re back online.',
      'Pas de connexion - cette photo s’enverra dès le retour du réseau.',
      'Sin conexión: esta foto se enviará sola cuando vuelvas a tener conexión.');
  String get photoPendingUpload => _t(
      'Photo will upload when you\'re back online',
      'La photo s’enverra dès le retour du réseau',
      'La foto se subirá cuando vuelvas a tener conexión');

  // --- Delivery runs: copy a run (builder) ---
  String get copyRun =>
      _t('Copy a run', 'Copier une tournée', 'Copiar una ruta');
  String get copyFromDate =>
      _t('Copy which day?', 'Copier quelle journée ?', '¿Copiar qué día?');
  String get runCopyNone => _t(
      'No run found for that day.',
      'Aucune tournée trouvée pour cette journée.',
      'No se encontró ninguna ruta para ese día.');
  String get runCopyConfirm => _t(
      'Replace the stops in this editor with the copied run?',
      'Remplacer les arrêts de cet éditeur par la tournée copiée ?',
      '¿Reemplazar las paradas de este editor con la ruta copiada?');
  String runCopied(int n) => _t('Copied $n stop(s).', '$n arrêt(s) copié(s).',
      'Se copiaron $n parada(s).');

  // --- Team: members + invites ---
  String get members => _t('Members', 'Membres', 'Miembros');
  String get pending => _t('Pending', 'En attente', 'Pendiente');
  String get resend => _t('Resend', 'Renvoyer', 'Reenviar');
  String get revoke => _t('Revoke', 'Révoquer', 'Revocar');
  String get alreadyMember => _t('This person already has an account.',
      'Cette personne a déjà un compte.', 'Esta persona ya tiene una cuenta.');
  String get alreadyInvited => _t(
      'An invite is already pending for this email.',
      'Une invitation est déjà en attente pour ce courriel.',
      'Ya hay una invitación pendiente para este correo.');
  String get inviteRevoked =>
      _t('Invite revoked.', 'Invitation révoquée.', 'Invitación revocada.');

  // --- Teams: named groups of crew members ---
  String get teams => _t('Teams', 'Équipes', 'Equipos');
  String get newTeam => _t('New team', 'Nouvelle équipe', 'Nuevo equipo');
  String get editTeam => _t('Edit team', 'Modifier l\'équipe', 'Editar equipo');
  String get deleteTeam =>
      _t('Delete team', 'Supprimer l\'équipe', 'Eliminar equipo');
  String get deleteTeamConfirm => _t(
      'Delete this team? Its members keep their accounts.',
      'Supprimer cette équipe ? Ses membres gardent leurs comptes.',
      '¿Eliminar este equipo? Sus miembros conservan sus cuentas.');
  String get teamName =>
      _t('Team name', 'Nom de l\'équipe', 'Nombre del equipo');
  String get noTeams =>
      _t('No teams yet', 'Aucune équipe pour le moment', 'Aún no hay equipos');
  String get teamSaved =>
      _t('Team saved', 'Équipe enregistrée', 'Equipo guardado');
  String get teamDeleted =>
      _t('Team deleted', 'Équipe supprimée', 'Equipo eliminado');

  // --- Tasks: detail screen ---
  String get deleteTask =>
      _t('Delete task', 'Supprimer la tâche', 'Eliminar tarea');
  String get deleteTaskConfirm => _t(
      'Delete this task? This cannot be undone.',
      'Supprimer cette tâche ? Cette action est irréversible.',
      '¿Eliminar esta tarea? Esto no se puede deshacer.');
  String get taskDeleted =>
      _t('Task deleted.', 'Tâche supprimée.', 'Tarea eliminada.');
  String get deleteStagedTaskNote => _t(
      'This task belongs to a roadmap stage — delete it from the roadmap.',
      'Cette tâche appartient à une étape de la feuille de route — supprimez-la depuis la feuille de route.',
      'Esta tarea pertenece a una etapa de la hoja de ruta: elimínala desde la hoja de ruta.');
  String get details => _t('Details', 'Détails', 'Detalles');
  String get schedule => _t('Schedule', 'Horaire', 'Horario');
  String get onSite => _t('On site', 'Sur place', 'En obra');
  String get startsAfter =>
      _t('Starts after', 'Commence après', 'Comienza después de');
  String get status => _t('Status', 'Statut', 'Estado');
  String get photoRequired =>
      _t('Photo required', 'Photo requise', 'Foto obligatoria');
  String tasksCount(int n) => _t(n == 1 ? '1 task' : '$n tasks',
      n == 1 ? '1 tâche' : '$n tâches', n == 1 ? '1 tarea' : '$n tareas');

  // --- Team: roles ---
  String get roleAdmin => _t('Admin', 'Admin', 'Admin');
  String get roleManager => _t('Manager', 'Gestionnaire', 'Gerente');
  String get roleWorker => _t('Worker', 'Ouvrier', 'Obrero');
  String get roleDelivery => _t('Delivery', 'Livreur', 'Repartidor');
  String get role => _t('Role', 'Rôle', 'Rol');
  String get roleUpdated =>
      _t('Role updated.', 'Rôle mis à jour.', 'Rol actualizado.');
  String get roleUpdateFailed => _t(
      'Could not change the role. Try again.',
      'Impossible de changer le rôle. Réessayez.',
      'No se pudo cambiar el rol. Inténtalo de nuevo.');

  // --- Tasks: pause / resume ---
  String get paused => _t('Paused', 'En pause', 'En pausa');
  String get pause => _t('Pause', 'Mettre en pause', 'Pausar');
  String get resume => _t('Resume', 'Reprendre', 'Reanudar');
  String get taskPaused =>
      _t('Task paused.', 'Tâche mise en pause.', 'Tarea en pausa.');
  String get taskResumed =>
      _t('Task resumed.', 'Tâche reprise.', 'Tarea reanudada.');

  // --- Notifications: in-app bell ---
  String get notifications =>
      _t('Notifications', 'Notifications', 'Notificaciones');
  String get markAllRead =>
      _t('Mark all read', 'Tout marquer comme lu', 'Marcar todo como leído');
  String get noNotifications => _t('No notifications yet.',
      'Aucune notification pour le moment.', 'Aún no hay notificaciones.');

  // --- Runs: today summary card (Board) ---
  String get todaysRuns =>
      _t("Today's runs", 'Tournées du jour', "Rutas de hoy");
  String runsToday(int n) => _t(
      n == 1 ? '1 run today' : '$n runs today',
      n == 1 ? '1 tournée aujourd’hui' : '$n tournées aujourd’hui',
      n == 1 ? '1 ruta hoy' : '$n rutas hoy');
  String get viewOnly => _t('View only', 'Lecture seule', 'Solo lectura');

  // --- Settings ---
  String get language => _t('Language', 'Langue', 'Idioma');
  String get nothingToday => _t('Nothing scheduled today.',
      "Rien de prévu aujourd'hui.", 'Nada programado hoy.');

  // --- Site roadmaps: stages ---
  String get tasks => _t('Tasks', 'Tâches', 'Tareas');
  String get roadmap => _t('Roadmap', 'Feuille de route', 'Hoja de ruta');
  String get createRoadmap =>
      _t('Create roadmap', 'Créer une feuille de route', 'Crear hoja de ruta');
  String get noRoadmapYet => _t(
      'No roadmap yet for this site.',
      'Aucune feuille de route pour ce chantier.',
      'Aún no hay hoja de ruta para esta obra.');
  String get noUnitRoadmapYet => _t(
      'No roadmap yet for this unit.',
      'Aucune feuille de route pour cette unité.',
      'Aún no hay hoja de ruta para esta unidad.');
  String get roadmapHint => _t(
      'Add stages in order — each stage unlocks only when the one before it is 100% done.',
      'Ajoutez les étapes dans l’ordre — chaque étape ne se débloque que lorsque la précédente est terminée à 100 %.',
      'Agrega las etapas en orden: cada etapa se desbloquea solo cuando la anterior está 100 % terminada.');
  String get houseTemplate =>
      _t('House template', 'Modèle maison', 'Plantilla de casa');
  String get blankRoadmap =>
      _t('Blank roadmap', 'Feuille de route vide', 'Hoja de ruta en blanco');
  String get roadmapTemplateHint => _t(
      'Starts with the 7 house stages: Foundation, Framing, Roofing, Plumbing, Electrical, Drywall, Paint & Finishing.',
      'Commence avec les 7 étapes maison : fondation, charpente, toiture, plomberie, électricité, cloison sèche, peinture et finition.',
      'Comienza con las 7 etapas de casa: cimientos, estructura, techo, plomería, electricidad, paneles de yeso, pintura y acabados.');
  String get savedTemplates => _t('Saved templates',
      'Modèles enregistrés', 'Plantillas guardadas');
  String get noTemplatesYet => _t('No saved templates yet.',
      'Aucun modèle enregistré.', 'Aún no hay plantillas guardadas.');
  String get saveAsTemplate => _t('Save as template',
      'Enregistrer comme modèle', 'Guardar como plantilla');
  String get templateName =>
      _t('Template name', 'Nom du modèle', 'Nombre de la plantilla');
  String get templateNameNeeded => _t(
      'Give the template a name first.',
      'Donnez d’abord un nom au modèle.',
      'Ponle primero un nombre a la plantilla.');
  String get templateSaved => _t('Roadmap saved as template.',
      'Feuille de route enregistrée comme modèle.',
      'Hoja de ruta guardada como plantilla.');
  String get deleteTemplate => _t(
      'Delete template', 'Supprimer le modèle', 'Eliminar plantilla');
  String deleteTemplateConfirm(String name) => _t(
      'Delete the template "$name"? It will be gone from every site.',
      'Supprimer le modèle « $name » ? Il disparaîtra de tous les chantiers.',
      '¿Eliminar la plantilla «$name»? Desaparecerá de todas las obras.');
  String get templateDeleted => _t('Template deleted.',
      'Modèle supprimé.', 'Plantilla eliminada.');
  String get copyRoadmap => _t(
      'Copy to site…', 'Copier vers un chantier…', 'Copiar a otra obra…');
  String get copyRoadmapTitle => _t('Copy roadmap to…',
      'Copier la feuille de route vers…', 'Copiar hoja de ruta a…');
  String get copyRoadmapHint => _t(
      'Stages and tasks copy over fresh — To do and unassigned.',
      'Les étapes et les tâches sont copiées à neuf — à faire et non assignées.',
      'Las etapas y las tareas se copian desde cero: por hacer y sin asignar.');
  String get roadmapCopied => _t('Roadmap copied.',
      'Feuille de route copiée.', 'Hoja de ruta copiada.');
  String get copyTargetHasRoadmap => _t(
      'That site already has a roadmap — delete it there first.',
      'Ce chantier a déjà une feuille de route — supprimez-la d’abord.',
      'Esa obra ya tiene una hoja de ruta; elimínala primero.');
  String get roadmapCreated =>
      _t('Roadmap created.', 'Feuille de route créée.', 'Hoja de ruta creada.');
  String get addStage => _t('Add stage', 'Ajouter une étape', 'Agregar etapa');
  String get stageName =>
      _t('Stage name', 'Nom de l’étape', 'Nombre de la etapa');
  String get stageNameNeeded => _t(
      'Give the stage a name first.',
      'Donnez d’abord un nom à l’étape.',
      'Ponle primero un nombre a la etapa.');
  String get stageAdded =>
      _t('Stage added.', 'Étape ajoutée.', 'Etapa agregada.');
  String get stage => _t('Stage', 'Étape', 'Etapa');
  String get noStage => _t('No stage', 'Aucune étape', 'Sin etapa');
  String get startStage =>
      _t('Start stage', 'Démarrer l’étape', 'Iniciar etapa');
  String get skipStage => _t('Skip', 'Passer', 'Omitir');
  String get unskipStage => _t('Un-skip', 'Rétablir', 'Restablecer');
  String get stageStarted =>
      _t('Stage started.', 'Étape démarrée.', 'Etapa iniciada.');
  String get stageSkipped =>
      _t('Stage skipped.', 'Étape ignorée.', 'Etapa omitida.');
  String get deleteStage =>
      _t('Delete stage', 'Supprimer l’étape', 'Eliminar etapa');
  String deleteStageConfirm(int n) => n == 1
      ? _t(
          'Delete this stage? Its 1 task will stay on the site without a stage.',
          'Supprimer cette étape ? Sa tâche restera sur le chantier, sans étape.',
          '¿Eliminar esta etapa? Su tarea quedará en la obra, sin etapa.')
      : _t(
          'Delete this stage? Its $n tasks will stay on the site without a stage.',
          'Supprimer cette étape ? Ses $n tâches resteront sur le chantier, sans étape.',
          '¿Eliminar esta etapa? Sus $n tareas quedarán en la obra, sin etapa.');
  String get stageDeleted =>
      _t('Stage deleted.', 'Étape supprimée.', 'Etapa eliminada.');
  String get deleteRoadmap => _t('Delete roadmap',
      'Supprimer la feuille de route', 'Eliminar hoja de ruta');
  String deleteRoadmapConfirm(int stages, int tasks) => _t(
      'Delete the whole roadmap? $stages stages will be removed. Their $tasks tasks will stay on the site without a stage.',
      'Supprimer toute la feuille de route ? $stages étapes seront supprimées. Leurs $tasks tâches resteront sur le chantier, sans étape.',
      '¿Eliminar toda la hoja de ruta? Se eliminarán $stages etapas. Sus $tasks tareas quedarán en la obra, sin etapa.');
  String get roadmapDeleted => _t('Roadmap deleted.',
      'Feuille de route supprimée.', 'Hoja de ruta eliminada.');
  String get addTask => _t('Add task', 'Ajouter une tâche', 'Agregar tarea');
  String get taskTitle =>
      _t('Task title', 'Titre de la tâche', 'Título de la tarea');
  String get unassigned => _t('Unassigned', 'Non assignée', 'Sin asignar');
  String moreAssignees(int n) =>
      _t('+$n more', '+$n de plus', '+$n más');
  String tasksDone(int done, int total) => _t('$done of $total tasks done',
      '$done sur $total tâches terminées', '$done de $total tareas terminadas');
  String stagesCount(int n) => _t(n == 1 ? '1 stage' : '$n stages',
      n == 1 ? '1 étape' : '$n étapes', n == 1 ? '1 etapa' : '$n etapas');
  String stageNumber(int n) => _t('Stage $n', 'Étape $n', 'Etapa $n');
  String stageStatusLabel(StageStatus status, {String? waitingOnName}) {
    switch (status) {
      case StageStatus.completed:
        return _t('Completed', 'Terminée', 'Terminada');
      case StageStatus.inProgress:
        return inProgress;
      case StageStatus.ready:
        return _t(
            'Ready to start — admin starts it',
            'Prête à démarrer — un admin la démarre',
            'Lista para empezar: la inicia un admin');
      case StageStatus.locked:
        return waitingOnName == null
            ? _t('Locked', 'Verrouillée', 'Bloqueada')
            : _t(
                'Locked — waiting on $waitingOnName',
                'Verrouillée — en attente de $waitingOnName',
                'Bloqueada: esperando a $waitingOnName');
      case StageStatus.skipped:
        return _t('Skipped', 'Ignorée', 'Omitida');
    }
  }

  // --- Site units: apartments inside a site ---
  String get units => _t('Units', 'Unités', 'Unidades');
  String get apartment => _t('Apartment', 'Appartement', 'Apartamento');
  String get addUnit => _t('Add unit', 'Ajouter une unité', 'Agregar unidad');
  String get unitName =>
      _t('Unit name', 'Nom de l’unité', 'Nombre de la unidad');
  String get unitNameNeeded => _t(
      'Give the unit a name first.',
      'Donnez d’abord un nom à l’unité.',
      'Ponle primero un nombre a la unidad.');
  String get unitAdded =>
      _t('Unit added.', 'Unité ajoutée.', 'Unidad agregada.');
  String get noUnit => _t('No unit', 'Aucune unité', 'Sin unidad');
  String get noUnits => _t('No units yet for this site.',
      'Aucune unité pour ce chantier.', 'Aún no hay unidades para esta obra.');
  String get renameUnit =>
      _t('Rename unit', 'Renommer l’unité', 'Renombrar unidad');
  String get unitRenamed =>
      _t('Unit renamed.', 'Unité renommée.', 'Unidad renombrada.');
  String get deleteUnit =>
      _t('Delete unit', 'Supprimer l’unité', 'Eliminar unidad');
  String deleteUnitConfirm(int n) => n == 1
      ? _t(
          'Delete this unit? Its 1 task will stay on the site without a unit.',
          'Supprimer cette unité ? Sa tâche restera sur le chantier, sans unité.',
          '¿Eliminar esta unidad? Su tarea quedará en la obra, sin unidad.')
      : _t(
          'Delete this unit? Its $n tasks will stay on the site without a unit.',
          'Supprimer cette unité ? Ses $n tâches resteront sur le chantier, sans unité.',
          '¿Eliminar esta unidad? Sus $n tareas quedarán en la obra, sin unidad.');
  String get unitDeleted =>
      _t('Unit deleted.', 'Unité supprimée.', 'Unidad eliminada.');
  String deleteUnitRoadmapNote(int n) => _t(
      'Its roadmap ($n stages) will be removed too.',
      'Sa feuille de route ($n étapes) sera aussi supprimée.',
      'Su hoja de ruta ($n etapas) también se eliminará.');

  // --- In-app chat: DMs, team channels, broadcasts ---
  String get chats => _t('Chats', 'Discussions', 'Chats');
  String get newMessage =>
      _t('New message', 'Nouveau message', 'Nuevo mensaje');
  String get messageSomeone =>
      _t('Message someone', 'Envoyer un message', 'Enviar un mensaje');
  String get typeMessage =>
      _t('Type a message', 'Écrivez un message', 'Escribe un mensaje');
  String get send => _t('Send', 'Envoyer', 'Enviar');
  String get noChats => _t(
      'No chats yet. Start one below.',
      'Aucune discussion. Commencez-en une ci-dessous.',
      'Aún no hay chats. Empieza uno abajo.');
  String get noMessagesYet => _t('No messages yet.',
      'Aucun message pour le moment.', 'Aún no hay mensajes.');
  String get message => _t('Message', 'Message', 'Mensaje');
  String get you => _t('You', 'Vous', 'Tú');
  String get unknownPerson => _t('Unknown', 'Inconnu', 'Desconocido');
  String membersCount(int n) => _t(n == 1 ? '1 member' : '$n members',
      n == 1 ? '1 membre' : '$n membres', n == 1 ? '1 miembro' : '$n miembros');
  String get broadcast => _t('Broadcast', 'Diffusion', 'Difusión');
  String get newBroadcast =>
      _t('New broadcast', 'Nouvelle diffusion', 'Nueva difusión');
  String get selectRecipients => _t('Select recipients',
      'Sélectionner les destinataires', 'Seleccionar destinatarios');
  String get broadcastHint => _t(
      'Each person gets it as a private message. Replies come back to you only.',
      'Chaque personne le reçoit comme un message privé. Les réponses ne reviennent qu’à vous.',
      'Cada persona lo recibe como mensaje privado. Las respuestas solo te llegan a ti.');
  String get broadcastSent =>
      _t('Broadcast sent.', 'Diffusion envoyée.', 'Difusión enviada.');
  String broadcastPartiallySent(int sent, int failed) => _t(
      'Broadcast sent to $sent ${sent == 1 ? 'person' : 'people'} — $failed did not receive it.',
      'Diffusion envoyée à $sent ${sent == 1 ? 'personne' : 'personnes'} — $failed ne l’ont pas reçue.',
      'Difusión enviada a $sent ${sent == 1 ? 'persona' : 'personas'}: $failed no la recibieron.');
  String get pickAtLeastOne => _t(
      'Pick at least one person first.',
      'Choisissez d’abord au moins une personne.',
      'Elige primero al menos a una persona.');
  String get messageNeeded => _t('Write the message first.',
      'Écrivez d’abord le message.', 'Escribe primero el mensaje.');
  String get couldNotOpenChat => _t(
      'Could not open the chat. Check your connection and try again.',
      'Impossible d’ouvrir la discussion. Vérifiez votre connexion et réessayez.',
      'No se pudo abrir el chat. Revisa tu conexión e inténtalo de nuevo.');
  String get couldNotSend => _t(
      'Could not send the message. Check your connection and try again.',
      'Impossible d’envoyer le message. Vérifiez votre connexion et réessayez.',
      'No se pudo enviar el mensaje. Revisa tu conexión e inténtalo de nuevo.');

  String get retry => _t('Retry', 'Réessayer', 'Reintentar');

  // --- Chat media: photos, videos, voice notes ---
  String get attachMedia => _t('Attach', 'Joindre', 'Adjuntar');
  String get takePhoto =>
      _t('Take a photo', 'Prendre une photo', 'Tomar una foto');
  String get choosePhoto =>
      _t('Choose a photo', 'Choisir une photo', 'Elegir una foto');
  String get recordVideo =>
      _t('Record a video', 'Enregistrer une vidéo', 'Grabar un video');
  String get chooseVideo =>
      _t('Choose a video', 'Choisir une vidéo', 'Elegir un video');
  String get voiceNote => _t('Voice note', 'Message vocal', 'Nota de voz');
  String get holdToRecord => _t('Hold to record', 'Maintenez pour enregistrer',
      'Mantén presionado para grabar');
  String get releaseToSend =>
      _t('Release to send', 'Relâchez pour envoyer', 'Suelta para enviar');
  String get dragToCancel => _t(
      'Drag away to cancel', 'Glissez pour annuler', 'Arrastra para cancelar');
  String get recording => _t('Recording…', 'Enregistrement…', 'Grabando…');
  String get voiceNoteTooShort => _t('Voice note too short.',
      'Message vocal trop court.', 'Nota de voz demasiado corta.');
  String get recordingFailed => _t(
      'Could not start recording. Check the microphone permission.',
      'Impossible de démarrer l’enregistrement. Vérifiez l’autorisation du micro.',
      'No se pudo iniciar la grabación. Revisa el permiso del micrófono.');
  String get mediaUploading => _t('Uploading…', 'Envoi en cours…', 'Subiendo…');
  String get mediaUploadFailed => _t(
      'Could not send the media. Check your connection and try again.',
      'Impossible d’envoyer le média. Vérifiez votre connexion et réessayez.',
      'No se pudo enviar el archivo. Revisa tu conexión e inténtalo de nuevo.');
  String get mediaTooLarge => _t(
      'That file is over 10 MB — pick a shorter video or a smaller photo.',
      'Ce fichier dépasse 10 Mo — choisissez une vidéo plus courte ou une photo plus petite.',
      'Ese archivo supera los 10 MB: elige un video más corto o una foto más pequeña.');
  String get mediaLabelPhoto => _t('[Photo]', '[Photo]', '[Foto]');
  String get mediaLabelVideo => _t('[Video]', '[Vidéo]', '[Video]');
  String get mediaLabelVoiceNote =>
      _t('[Voice note]', '[Message vocal]', '[Nota de voz]');

  // --- Photo viewer: zoom, download, share ---
  String get download => _t('Download', 'Télécharger', 'Descargar');
  String get photoSaved =>
      _t('Saved to Photos.', 'Enregistré dans Photos.', 'Guardado en Fotos.');
  String get photoSaveFailed => _t(
      'Could not save the photo. Check the Photos permission and try again.',
      'Impossible d’enregistrer la photo. Vérifiez l’autorisation Photos et réessayez.',
      'No se pudo guardar la foto. Revisa el permiso de Fotos e inténtalo de nuevo.');
  String get couldNotShare => _t('Could not share the photo.',
      'Impossible de partager la photo.', 'No se pudo compartir la foto.');

  // ---- Delivery driver ----
  String get driverHelloMorning => lang == 'fr' ? 'Bon matin' : 'Good morning';
  String get driverHelloAfternoon =>
      lang == 'fr' ? 'Bon après-midi' : 'Good afternoon';
  String get driverHelloEvening => lang == 'fr' ? 'Bonsoir' : 'Good evening';
  String driverNextStop(int n) =>
      lang == 'fr' ? 'Prochain arrêt $n' : 'Next stop $n';
  String get driverAllDone =>
      lang == 'fr' ? 'Tournée terminée 🎉' : 'Run finished 🎉';
  String get driverNoStopsLeft =>
      lang == 'fr' ? 'Tous les arrêts sont faits.' : 'All stops are done.';
  String driverStopsDone(int done, int total) =>
      lang == 'fr' ? '$done sur $total arrêts' : '$done of $total stops';
  String get driverImHere => lang == 'fr' ? 'Je suis là' : 'I\'m here';
  String get driverArrivedMarked =>
      lang == 'fr' ? 'Arrivée notée.' : 'Arrival noted.';
  String get driverDelayed => lang == 'fr' ? 'En retard' : 'Delayed';
  String driverDelayedBy(int minutes) => lang == 'fr'
      ? 'Retard de $minutes min noté.'
      : 'Delayed by $minutes min noted.';
  String get driverDelay15 => lang == 'fr' ? 'Retard 15 min' : 'Delayed 15 min';
  String get driverDelay30 => lang == 'fr' ? 'Retard 30 min' : 'Delayed 30 min';
  String get driverDirections => lang == 'fr' ? 'Itinéraire' : 'Directions';
  String get driverDropOff => lang == 'fr' ? 'Dépôt' : 'Drop-off';
  String get driverPickup => lang == 'fr' ? 'Ramassage' : 'Pickup';
  String driverItemsCount(int n) =>
      lang == 'fr' ? '$n article(s)' : '$n item(s)';
  String get driverMileage => lang == 'fr' ? 'Kilométrage' : 'Mileage';
  String get driverOdometerStart =>
      lang == 'fr' ? 'Odomètre au départ (km)' : 'Odometer at start (km)';
  String get driverOdometerEnd =>
      lang == 'fr' ? 'Odomètre à l\'arrivée (km)' : 'Odometer at end (km)';
  String get driverSaveMileage => lang == 'fr' ? 'Enregistrer' : 'Save';
  String driverDistanceKm(int km) =>
      lang == 'fr' ? '$km km aujourd\'hui' : '$km km today';
  String get driverMileageSaved =>
      lang == 'fr' ? 'Kilométrage enregistré.' : 'Mileage saved.';
  String get driverMileageInvalid => lang == 'fr'
      ? 'Vérifiez les relevés : l\'arrivée doit être après le départ.'
      : 'Check the readings: end must be after start.';
  String get driverCarriedOver =>
      lang == 'fr' ? 'reporté(s) d\'hier' : 'carried over from yesterday';
  String driverCarriedBanner(int n) => lang == 'fr'
      ? '$n arrêt(s) reporté(s) d\'hier'
      : '$n stop(s) carried over from yesterday';
  String get driverAutoAdded =>
      lang == 'fr' ? 'Ajouté automatiquement' : 'Auto-added';
  String get driverArrivedAt => lang == 'fr' ? 'Arrivé à' : 'Arrived at';
  String get driverPhotoProof =>
      lang == 'fr' ? 'Photo de preuve' : 'Photo proof';
  String get driverPhotoHint => lang == 'fr'
      ? 'Une photo est appréciée, mais pas obligatoire pour terminer l\'arrêt.'
      : 'A photo is appreciated but not required to finish the stop.';
  String get driverRunUpdated =>
      lang == 'fr' ? 'Tournée mise à jour.' : 'Run updated.';
  String get driverNoRunYet => lang == 'fr'
      ? 'Aucune tournée aujourd\'hui pour l\'instant.'
      : 'No run yet today.';
  String get driverRunComing => lang == 'fr'
      ? 'Votre prochaine tournée apparaîtra ici.'
      : 'Your next run will appear here.';
  String get driverUpcomingRun =>
      lang == 'fr' ? 'Prochaine tournée' : 'Upcoming run';
  String stopsCount(int n) => lang == 'fr' ? '$n arrêt(s)' : '$n stop(s)';

  // ---- Material requests ----
  String get materialRequests => _t('Material requests',
      'Demandes de matériaux', 'Solicitudes de materiales');
  String get requestMaterials =>
      _t('Request materials', 'Demander des matériaux', 'Solicitar materiales');
  String get materialItem => _t('Item', 'Article', 'Artículo');
  String get materialItemHint =>
      _t('What do you need?', 'De quoi avez-vous besoin ?', '¿Qué necesitas?');
  String get materialQuantity => _t('Quantity', 'Quantité', 'Cantidad');
  String get materialNeededBy =>
      _t('Needed by', 'Besoin pour le', 'Necesario para el');
  String get materialNoDate => _t('No date', 'Pas de date', 'Sin fecha');
  String get materialNoteOptional =>
      _t('Note (optional)', 'Note (facultatif)', 'Nota (opcional)');
  String get materialRequestSent => _t(
      'Request sent to the managers.',
      'Demande envoyée aux responsables.',
      'Solicitud enviada a los responsables.');
  String materialRequestFailed(String e) => _t('Could not send the request: $e',
      'Envoi impossible : $e', 'No se pudo enviar la solicitud: $e');
  String get materialRequestNeedsItem => _t('Name the item first.',
      'Nommez d’abord l’article.', 'Nombra primero el artículo.');
  String get materialRequestNeedsQty => _t(
      'Quantity must be at least 1.',
      'La quantité doit être d’au moins 1.',
      'La cantidad debe ser al menos 1.');
  String get materialRequestApprove => _t('Approve', 'Approuver', 'Aprobar');
  String get materialRequestDeny => _t('Deny', 'Refuser', 'Rechazar');
  String get materialRequestDenyReason =>
      _t('Reason for refusing', 'Raison du refus', 'Motivo del rechazo');
  String get materialRequestDenied =>
      _t('Request denied.', 'Demande refusée.', 'Solicitud rechazada.');
  String get materialRequestApproved =>
      _t('Request approved.', 'Demande approuvée.', 'Solicitud aprobada.');
  String get materialRequestAddToRun => _t('Add to today’s run',
      'Ajouter à la tournée du jour', 'Agregar a la ruta de hoy');
  String get materialRequestAddedToRun => _t('Added to today’s run.',
      'Ajouté à la tournée du jour.', 'Agregado a la ruta de hoy.');
  String get materialRequestNoRunToday => _t(
      'No run today — the request stays approved.',
      'Aucune tournée aujourd’hui — la demande reste approuvée.',
      'No hay ruta hoy: la solicitud sigue aprobada.');
  String get materialRequestStatusRequested =>
      _t('Requested', 'Demandée', 'Solicitada');
  String get materialRequestStatusApproved =>
      _t('Approved', 'Approuvée', 'Aprobada');
  String get materialRequestStatusOnRun =>
      _t('On the run', 'En tournée', 'En ruta');
  String get materialRequestStatusDelivered =>
      _t('Delivered', 'Livrée', 'Entregada');
  String get materialRequestStatusDenied =>
      _t('Denied', 'Refusée', 'Rechazada');
  String get materialRequestFilterOpen => _t('Open', 'Ouvertes', 'Abiertas');
  String get materialRequestFilterOnRun =>
      _t('On the run', 'En tournée', 'En ruta');
  String get materialRequestNoRequests => _t('No material requests yet.',
      'Aucune demande de matériaux.', 'Aún no hay solicitudes de materiales.');
  String materialRequestedBy(String name) =>
      _t('Requested by $name', 'Demandée par $name', 'Solicitada por $name');
  String materialRequestOnRunFor(String date) => _t('On the run for $date',
      'En tournée pour le $date', 'En ruta para el $date');
  String get materialRequestApprovedTitle => _t('Approved material requests',
      'Demandes approuvées', 'Solicitudes aprobadas');
  String get materialRequestTabRequests =>
      _t('Requests', 'Demandes', 'Solicitudes');
  String get materialRequestTabHistory =>
      _t('History', 'Historique', 'Historial');
  String get materialRequestDelete => _t('Delete', 'Supprimer', 'Eliminar');
  String get materialRequestDeleteTitle => _t(
      "Delete this request? This can't be undone.",
      'Supprimer cette demande ? Cette action est irréversible.',
      '¿Eliminar esta solicitud? Esto no se puede deshacer.');
  String get materialRequestDeleted =>
      _t('Request deleted.', 'Demande supprimée.', 'Solicitud eliminada.');

  // ---- Clock-in by site + hours ----
  String get hours => _t('Hours', 'Heures', 'Horas');
  String get clockIn => _t('Clock in', 'Pointer', 'Registrar entrada');
  String get clockOut =>
      _t('Clock out', 'Pointer la sortie', 'Registrar salida');
  String get clockInAtSite =>
      _t('Clock in at', 'Pointer à', 'Registrar entrada en');
  String clockedInAt(String site) => _t(
      'Clocked in at $site', 'Pointé à $site', 'Entrada registrada en $site');

  /// Short live status for the Hours person card: the site and
  /// clock-in time already show on the profile status card, so
  /// the card line carries only the live "so far" time — short
  /// enough to fit on one line at phone width.
  String clockedInFor(String duration) =>
      _t('Clocked in · $duration', 'Pointé · $duration', 'Fichado · $duration');
  String clockedInSince(String time) =>
      _t('Since $time', 'Depuis $time', 'Desde las $time');
  String get clockInHint => _t(
      'Your location is checked once, at the tap — never tracked through the day.',
      'Votre position est vérifiée une seule fois, au moment du pointage — jamais suivie pendant la journée.',
      'Tu ubicación se verifica una sola vez, al registrar: nunca se te sigue durante el día.');
  String get notClockedIn => _t(
      'Not clocked in yet.', 'Pas encore pointé.', 'Sin entrada registrada.');
  String clockInSwitched(String from, String to) => _t(
      'Clocked out of $from, clocked in at $to.',
      'Sortie de $from, pointé à $to.',
      'Salida de $from, entrada en $to.');

  /// One-tap site switch: the worker is clocked in at another
  /// site and is now inside this site's fence, so the button
  /// offers the move instead of a plain clock-out.
  String switchToSite(String site) =>
      _t('Switch to $site', 'Passer à $site', 'Cambiar a $site');
  String get clockedInHere => _t('Already clocked in here.', 'Déjà pointé ici.',
      'Ya registraste tu entrada aquí.');

  /// Clock-in outside every fence: the day entry opened with
  /// no site, and the visit log records where the worker was.
  String get clockedInForDay => _t('Clocked in for the day.',
      'Pointé pour la journée.', 'Entrada registrada para el día.');

  /// Short status for an open day entry (no site to name).
  String get clockedIn => _t('Clocked in', 'Pointé', 'Registrado');

  /// A day entry with no clock-in site.
  String get noSite => _t('No site', 'Aucun chantier', 'Sin obra');

  /// Week total header on the profile Clock-in tab, and the
  /// week line on Team tiles: "This week: 7 h 32 min".
  String thisWeekHours(String hours) =>
      _t('This week: $hours', 'Cette semaine : $hours', 'Esta semana: $hours');

  /// Site visits recorded during a clocked-in day.
  String get visits => _t('Visits', 'Visites', 'Visitas');

  /// The open visit: the worker is still at that site.
  String get hereNow => _t('Here now', 'Ici en ce moment', 'Aquí ahora');
  String get noVisitsYet => _t(
      'No site visits yet.',
      'Aucune visite de chantier pour l’instant.',
      'Aún no hay visitas a obras.');
  String clockInFailed(String e) => _t('Could not clock in: $e',
      'Pointage impossible : $e', 'No se pudo registrar la entrada: $e');
  String clockOutFailed(String e) => _t('Could not clock out: $e',
      'Sortie impossible : $e', 'No se pudo registrar la salida: $e');
  String get clockInLocationUnavailable => _t(
      'Location unavailable — clocked in anyway, flagged for review.',
      'Position indisponible — pointage enregistré quand même, à vérifier.',
      'Ubicación no disponible: entrada registrada de todos modos, marcada para revisión.');

  /// Clock-in blocked: the worker is outside the site's fence.
  /// Distances are whole metres.
  String clockInBlockedOutsideRadius(String site, int distance, int radius) => _t(
      'You are $distance m from $site — move within $radius m to clock in.',
      'Vous êtes à $distance m de $site — rapprochez-vous à moins de $radius m pour pointer.',
      'Estás a $distance m de $site: acércate a menos de $radius m para registrar tu entrada.');

  /// Pick-a-site fallback: blocked outside every fence, the
  /// worker may still clock in at a site they pick — the
  /// entry is flagged for review (the server verifies the fix
  /// against the picked site's fence, so it lands flagged
  /// with 'outside-radius').
  String get clockInPickSiteTitle => _t('Clock in at another site?',
      'Pointer à un autre chantier ?', '¿Registrar entrada en otra obra?');
  String clockInPickSiteBody(String site, int distance, int radius) => _t(
      'You are $distance m from $site — outside the $radius m fence. Pick a site to clock in at instead. The entry will be flagged for review.',
      'Vous êtes à $distance m de $site — hors du rayon de $radius m. Choisissez un chantier pour pointer quand même. Le pointage sera signalé pour vérification.',
      'Estás a $distance m de $site, fuera del radio de $radius m. Elige una obra para registrar tu entrada. El registro quedará marcado para revisión.');
  String clockInPickedSiteFlagged(String site) => _t(
      'Clocked in at $site — flagged for review, outside the site radius.',
      'Pointé à $site — signalé pour vérification, hors du rayon du chantier.',
      'Entrada registrada en $site: marcada para revisión, fuera del radio de la obra.');

  /// No sites exist yet: clock-in has nothing to pick from.
  String get clockInNoSites => _t('No sites yet — ask an admin to add one.',
      'Aucun chantier pour le moment — demandez à un administrateur d’en ajouter un.',
      'Aún no hay obras: pide a un administrador que agregue una.');

  /// The fix could not be taken at the tap: location services
  /// off, or permission denied. The clock-in still goes ahead
  /// flagged — this tells the worker why it was not verified.
  String get locationServicesOff => _t(
      'Location services are off — turn location on in your phone settings.',
      'Les services de localisation sont désactivés — activez la localisation dans les réglages de votre téléphone.',
      'Los servicios de ubicación están desactivados: actívalos en los ajustes de tu teléfono.');
  String get locationPermissionDenied => _t(
      'Location permission is denied — allow it in Settings to verify clock-ins.',
      'L’autorisation de localisation est refusée — autorisez-la dans les réglages pour vérifier les pointages.',
      'El permiso de ubicación está denegado: permítelo en Ajustes para verificar las entradas.');
  String get locationUnavailable => _t(
      'Location unavailable — this entry is flagged for review.',
      'Position indisponible — ce pointage est signalé pour vérification.',
      'Ubicación no disponible: este registro queda marcado para revisión.');

  /// Tag on history entries the auto clock-in created.
  String get autoTag => _t('Auto', 'Auto', 'Auto');

  /// Foreground-service notification while the work route is
  /// being recorded (Android; iOS shows the system location
  /// indicator instead).
  String get trackingNotificationTitle => _t('Recording your work route',
      'Enregistrement de votre trajet', 'Registrando tu ruta de trabajo');
  String get trackingNotificationText => _t(
      'DyadeSpace saves your location every 5 minutes while you are clocked in. It stops when you clock out.',
      'DyadeSpace enregistre votre position toutes les 5 minutes pendant que vous êtes pointé. Cela s’arrête à la sortie.',
      'DyadeSpace guarda tu ubicación cada 5 minutos mientras estás registrado. Se detiene cuando registras tu salida.');
  String get totalHours =>
      _t('Total hours', 'Total des heures', 'Horas totales');
  String hoursEntriesCount(int n) => _t(
      n == 1 ? '1 entry' : '$n entries',
      n == 1 ? '1 pointage' : '$n pointages',
      n == 1 ? '1 registro' : '$n registros');
  String get hoursNoEntries => _t(
      'No hours recorded for this period.',
      'Aucune heure enregistrée pour cette période.',
      'No hay horas registradas para este período.');
  String get hoursVerified => _t('Verified', 'Vérifié', 'Verificado');
  String get hoursFlagged => _t('Flagged', 'Signalé', 'Señalado');
  String get hoursStillClockedIn =>
      _t('Still clocked in', 'Toujours pointé', 'Todavía registrado');
  String get hoursEditEntry =>
      _t('Edit hours', 'Modifier les heures', 'Editar horas');
  String get hoursEntrySaved =>
      _t('Hours updated.', 'Heures mises à jour.', 'Horas actualizadas.');
  String hoursEntrySaveFailed(String e) => _t(
      'Could not save the hours: $e',
      'Impossible d’enregistrer les heures : $e',
      'No se pudieron guardar las horas: $e');
  String get hoursExportCsv => _t('Export CSV', 'Exporter CSV', 'Exportar CSV');
  String get hoursCsvShared => _t(
      'Hours file ready to share.',
      'Fichier des heures prêt à partager.',
      'Archivo de horas listo para compartir.');
  String get hoursCsvFailed => _t(
      'Could not create the hours file.',
      'Impossible de créer le fichier des heures.',
      'No se pudo crear el archivo de horas.');
  String hoursWeekLabel(String start, String end) => '$start – $end';
  String get hoursPreviousWeek =>
      _t('Previous week', 'Semaine précédente', 'Semana anterior');
  String get hoursNextWeek =>
      _t('Next week', 'Semaine suivante', 'Semana siguiente');
  String get hoursClockInTime =>
      _t('Clock-in time', 'Heure d’arrivée', 'Hora de entrada');
  String get hoursClockOutTime =>
      _t('Clock-out time', 'Heure de départ', 'Hora de salida');
  String get hoursInvalidTimes => _t(
      'Clock-out must be after clock-in.',
      'La sortie doit être après l’arrivée.',
      'La salida debe ser después de la entrada.');
  String get hoursWorker => _t('Worker', 'Travailleur', 'Trabajador');
  String get hoursAllSites =>
      _t('All sites', 'Tous les chantiers', 'Todas las obras');

  /// Maps a TimeEntry flagReason code to its label.
  String flagReasonLabel(String? code) {
    switch (code) {
      case 'outside-radius':
        return _t('Outside site radius', 'Hors du rayon du chantier',
            'Fuera del radio de la obra');
      case 'clock-out-outside-radius':
        return _t(
            'Clock-out outside site radius',
            'Sortie hors du rayon du chantier',
            'Salida fuera del radio de la obra');
      case 'no-location':
        return _t('Location unavailable', 'Position indisponible',
            'Ubicación no disponible');
      case 'no-site-location':
        return _t(
            'No site location set',
            'Aucune position définie pour ce chantier',
            'Sin ubicación definida para esta obra');
      default:
        return _t('Flagged', 'Signalé', 'Señalado');
    }
  }

  // ---- Site GPS location ----
  String get siteLocation => _t('Site location (GPS)',
      'Position du chantier (GPS)', 'Ubicación de la obra (GPS)');
  String get siteLatitude => _t('Latitude', 'Latitude', 'Latitud');
  String get siteLongitude => _t('Longitude', 'Longitude', 'Longitud');
  String get siteLocationHint => _t(
      'Optional — used to check clock-ins at this site.',
      'Facultatif — sert à vérifier les pointages à ce chantier.',
      'Opcional: sirve para verificar las entradas en esta obra.');
  String get siteUseMyLocation =>
      _t('Use my location', 'Utiliser ma position', 'Usar mi ubicación');
  String get siteLocationSet =>
      _t('Location set.', 'Position enregistrée.', 'Ubicación guardada.');
  String get siteRadius => _t(
      'Clock-in radius (m)', 'Rayon de pointage (m)', 'Radio de registro (m)');
  String get siteRadiusHint => _t(
      'How far from the pin counts as "at the site". 100 m when empty.',
      'À quelle distance de l’épingle on est encore « sur le chantier ». 100 m si vide.',
      'A qué distancia del pin se considera «en la obra». 100 m si está vacío.');

  /// "Radius 100 m" line under a site's name (Sites lists).
  String siteRadiusDisplay(int metres) => _t(
        'Radius $metres m',
        'Rayon $metres m',
        'Radio $metres m',
      );

  // ---- Bulk invite ----
  String get bulkInvite =>
      _t('Bulk invite', 'Invitation en lot', 'Invitación masiva');
  String get bulkInvitePaste =>
      _t('Paste emails', 'Coller des courriels', 'Pegar correos');
  String get bulkInviteImport =>
      _t('Import CSV', 'Importer un CSV', 'Importar CSV');
  String get bulkInvitePasteHint => _t(
      'One email per line, or separated by commas.',
      'Un courriel par ligne, ou séparés par des virgules.',
      'Un correo por línea, o separados por comas.');
  String get bulkInviteSheetsHint => _t(
      'Google Sheets: export your sheet as CSV (File → Download → CSV), then import the file here.',
      'Google Sheets : exportez votre feuille en CSV (Fichier → Télécharger → CSV), puis importez le fichier ici.',
      'Google Sheets: exporta tu hoja como CSV (Archivo → Descargar → CSV) y luego importa el archivo aquí.');
  String get bulkInviteChooseFile => _t(
      'Choose a CSV file', 'Choisir un fichier CSV', 'Elegir un archivo CSV');
  String bulkInviteFilePicked(int n) => _t(
      n == 1 ? '1 email found in the file.' : '$n emails found in the file.',
      n == 1
          ? '1 courriel trouvé dans le fichier.'
          : '$n courriels trouvés dans le fichier.',
      n == 1
          ? 'Se encontró 1 correo en el archivo.'
          : 'Se encontraron $n correos en el archivo.');
  String get bulkInviteFileReadFailed => _t('Could not read that file.',
      'Impossible de lire ce fichier.', 'No se pudo leer ese archivo.');
  String get bulkInviteNoValidEmails => _t('No valid emails found.',
      'Aucun courriel valide trouvé.', 'No se encontraron correos válidos.');
  String get bulkInviteCreate =>
      _t('Create invites', 'Créer les invitations', 'Crear invitaciones');
  String bulkInviteCreated(int n) => _t(
      n == 1 ? '1 invite created.' : '$n invites created.',
      n == 1 ? '1 invitation créée.' : '$n invitations créées.',
      n == 1 ? 'Se creó 1 invitación.' : 'Se crearon $n invitaciones.');
  String get bulkInviteSkipped => _t('Skipped', 'Ignorées', 'Omitidas');
  String get bulkInviteAlreadyMember =>
      _t('already has an account', 'a déjà un compte', 'ya tiene una cuenta');
  String get bulkInviteAlreadyInvited =>
      _t('already invited', 'déjà invité', 'ya fue invitado');
  String get bulkInviteInvalid =>
      _t('invalid email', 'courriel invalide', 'correo inválido');
  String get bulkInviteDone => _t('Done', 'Terminé', 'Terminado');
  String get bulkInviteRole =>
      _t('Role for everyone', 'Rôle pour tous', 'Rol para todos');

  // ---- Clock-in/out map view ----
  String get clockInLocation =>
      _t('Clock-in location', 'Lieu du pointage', 'Lugar de entrada');
  String get clockOutLocation =>
      _t('Clock-out location', 'Lieu de la sortie', 'Lugar de salida');
  String get openInMaps =>
      _t('Open in Maps', 'Ouvrir dans Maps', 'Abrir en Maps');
  String get openInMapsFailed => _t('Could not open Maps.',
      'Impossible d’ouvrir Maps.', 'No se pudo abrir Maps.');
  String get noLocationForEntry => _t(
      'No location was recorded for this entry.',
      'Aucune position enregistrée pour cette entrée.',
      'No se registró ubicación para esta entrada.');

  // ---- Worker profiles + profile photos ----
  String get viewProfile => _t('View profile', 'Voir le profil', 'Ver perfil');
  String get profileHistory => _t(
      'Clock-in history', 'Historique des pointages', 'Historial de entradas');
  String get profileNoHistory => _t('No clock-ins yet.',
      'Aucun pointage pour le moment.', 'Aún no hay entradas.');
  String get addProfilePhoto => _t('Add profile photo',
      'Ajouter une photo de profil', 'Agregar foto de perfil');
  String get changeProfilePhoto => _t('Change profile photo',
      'Changer la photo de profil', 'Cambiar foto de perfil');
  String get profilePhotoUploadFailed => _t(
      'Could not upload the photo. Try again.',
      'Impossible d’envoyer la photo. Réessayez.',
      'No se pudo subir la foto. Inténtalo de nuevo.');
  String get photoUpdated => _t('Profile photo updated.',
      'Photo de profil mise à jour.', 'Foto de perfil actualizada.');

  // ---- Board actions sheet ----
  String get actions => _t('Actions', 'Actions', 'Acciones');

  // ---- Settings ----
  String get settings => _t('Settings', 'Réglages', 'Ajustes');
  String get appearance => _t('Appearance', 'Apparence', 'Apariencia');
  String get notifTaskAssigned => _t(
      'New task assigned', 'Nouvelle tâche assignée', 'Nueva tarea asignada');
  String get notifClockInOut => _t('Clock-in / clock-out alerts',
      'Alertes de pointage', 'Alertas de entrada y salida');
  String get notifChatMessages =>
      _t('Chat messages', 'Messages de discussion', 'Mensajes de chat');
  String get notifEodReport => _t('End-of-day report',
      'Rapport de fin de journée', 'Informe de fin de día');
  String get eodReportTime =>
      _t('Report time', 'Heure du rapport', 'Hora del informe');
  String get account => _t('Account', 'Compte', 'Cuenta');
  String get appVersion =>
      _t('App version', 'Version de l’application', 'Versión de la app');

  // ---- Web control center ----
  String get overview => _t('Overview', 'Aperçu', 'Resumen');
  String get controlCenter =>
      _t('Control Center', 'Centre de contrôle', 'Centro de control');
  String get whosOnSite => _t('Who’s on site right now', 'Qui est sur place',
      'Quién está en obra ahora');
  String get clockedInNow =>
      _t('Clocked in now', 'Pointés maintenant', 'Fichados ahora');
  String get hoursThisWeek =>
      _t('Hours this week', 'Heures cette semaine', 'Horas esta semana');
  String get tasksToday => _t('Tasks today', 'Tâches du jour', 'Tareas de hoy');
  String get needsAttention =>
      _t('Needs attention', 'À surveiller', 'Necesita atención');
  String get seansRun =>
      _t('Drew’s run today', 'Tournée de Drew aujourd’hui', 'Ruta de Drew hoy');
  String get viewRun => _t('View run', 'Voir la tournée', 'Ver ruta');
  String get crew => _t('Crew', 'Équipe', 'Equipo');
  String get manage => _t('Manage', 'Gérer', 'Gestionar');
  String get workspace =>
      _t('Workspace', 'Espace de travail', 'Espacio de trabajo');
  String get managersOnly => _t(
      'The control center is for admins and managers.',
      'Le centre de contrôle est réservé aux admins et aux gestionnaires.',
      'El centro de control es solo para administradores y gerentes.');
  String get review => _t('Review', 'À revoir', 'Revisar');
  String get viewOnMap =>
      _t('View on map', 'Voir sur la carte', 'Ver en el mapa');
  String get onRun => _t('On run', 'En tournée', 'En ruta');
  String sinceTime(String time) =>
      _t('since $time', 'depuis $time', 'desde las $time');
  String get noRunToday =>
      _t('No run today', 'Aucune tournée aujourd’hui', 'Sin ruta hoy');
  String get close => _t('Close', 'Fermer', 'Cerrar');
  String get allWorkers =>
      _t('All workers', 'Tous les travailleurs', 'Todos los trabajadores');
  String get noWorkersYet => _t('No workers yet',
      'Aucun travailleur pour l’instant', 'Aún no hay trabajadores');
  String get noStops => _t('No stops', 'Aucun arrêt', 'Sin paradas');
  String odometerRange(String start, String end) => _t(
      'Odometer: $start → $end',
      'Odomètre : $start → $end',
      'Odómetro: $start → $end');

  // --- Audit fixes (Nov 14, 2026): auth, voice notes, confirmations,
  // privacy / Law 25, send + playback failures. ---
  String get forgotPassword => _t(
      'Forgot password?', 'Mot de passe oublié ?', '¿Olvidaste tu contraseña?');
  String get resetEmailSent => _t(
      'Password reset email sent. Check your inbox.',
      'Courriel de réinitialisation envoyé. Vérifiez votre boîte de réception.',
      'Correo para restablecer la contraseña enviado. Revisa tu bandeja de entrada.');
  String get showPassword =>
      _t('Show password', 'Afficher le mot de passe', 'Mostrar contraseña');
  String get hidePassword =>
      _t('Hide password', 'Masquer le mot de passe', 'Ocultar contraseña');

  /// Friendly, localised message for a FirebaseAuthException code.
  /// Raw Firebase error text must never be shown on screen.
  String authError(String code) {
    switch (code) {
      case 'invalid-email':
        return _t(
            'That email address does not look right.',
            'Cette adresse courriel ne semble pas valide.',
            'Esa dirección de correo no parece válida.');
      case 'user-not-found':
        return _t(
            'No account was found for this email.',
            'Aucun compte trouvé pour ce courriel.',
            'No se encontró ninguna cuenta para este correo.');
      case 'wrong-password':
        return _t(
            'Wrong password. Try again.',
            'Mot de passe incorrect. Réessayez.',
            'Contraseña incorrecta. Inténtalo de nuevo.');
      case 'invalid-credential':
        return _t(
            'Those sign-in details are not right.',
            'Ces identifiants ne sont pas corrects.',
            'Esos datos de inicio de sesión no son correctos.');
      case 'weak-password':
        return _t(
            'That password is too weak. Use at least 6 characters.',
            'Ce mot de passe est trop faible. Utilisez au moins 6 caractères.',
            'Esa contraseña es demasiado débil. Usa al menos 6 caracteres.');
      case 'email-already-in-use':
        return _t(
            'An account already exists for this email.',
            'Un compte existe déjà pour ce courriel.',
            'Ya existe una cuenta para este correo.');
      case 'too-many-requests':
        return _t(
            'Too many attempts. Wait a few minutes and try again.',
            'Trop de tentatives. Attendez quelques minutes puis réessayez.',
            'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.');
      case 'network-request-failed':
        return _t(
            'No connection. Check your internet and try again.',
            'Pas de connexion. Vérifiez votre connexion internet puis réessayez.',
            'Sin conexión. Revisa tu conexión a internet e inténtalo de nuevo.');
      case 'user-disabled':
        return _t('This account has been disabled.',
            'Ce compte a été désactivé.', 'Esta cuenta ha sido desactivada.');
      case 'operation-not-allowed':
        return _t(
            'Sign-in is not available right now.',
            'La connexion n’est pas disponible pour l’instant.',
            'El inicio de sesión no está disponible ahora mismo.');
      default:
        return _t(
            'Something went wrong. Try again.',
            'Quelque chose a mal tourné. Réessayez.',
            'Algo salió mal. Inténtalo de nuevo.');
    }
  }

  String get micPermissionTitle => _t(
      'Microphone needed', 'Microphone nécessaire', 'Se necesita el micrófono');
  String get micPermissionBody => _t(
      'Voice notes need microphone access. Allow it in your phone settings to record.',
      'Les notes vocales nécessitent l’accès au microphone. Autorisez-le dans les réglages du téléphone pour enregistrer.',
      'Las notas de voz necesitan acceso al micrófono. Permítelo en los ajustes del teléfono para grabar.');
  String get openSettings =>
      _t('Open settings', 'Ouvrir les réglages', 'Abrir ajustes');
  String get confirmStartTask =>
      _t('Start this task?', 'Commencer cette tâche ?', '¿Empezar esta tarea?');
  String get confirmApproveRequest => _t('Approve this request?',
      'Approuver cette demande ?', '¿Aprobar esta solicitud?');
  String get confirmDeleteStopDraft => _t('Delete this stop draft?',
      'Supprimer ce brouillon d’arrêt ?', '¿Eliminar este borrador de parada?');
  String get confirmSignOut =>
      _t('Sign out?', 'Se déconnecter ?', '¿Cerrar sesión?');

  String get privacyNoticeTitle =>
      _t('Privacy', 'Confidentialité', 'Privacidad');
  String get privacyNoticeBody => _t(
      'DyadeSpace uses your location only when you clock in or out, to confirm you are at the site — one GPS fix per tap, never tracked through the day. If you turn on auto clock-in, it also checks your location in the background (about every 15 minutes) to clock you in and out at sites, and saves your work route — one point every 5 minutes — while you are clocked in. Nothing is recorded when you are off the clock. Photos you take in the app are visible to the crew. Your hours are used for payroll. Questions? Ask Alex or Sam.',
      'DyadeSpace utilise votre position uniquement quand vous pointez à l’arrivée ou au départ, pour confirmer que vous êtes sur le chantier — une seule position par pointage, jamais de suivi en continu. Si vous activez le pointage automatique, il vérifie aussi votre position en arrière-plan (environ toutes les 15 minutes) pour vous pointer aux chantiers, et enregistre votre trajet de travail — un point toutes les 5 minutes — pendant que vous êtes pointé. Rien n’est enregistré hors des heures de travail. Les photos prises dans l’application sont visibles par l’équipe. Vos heures servent à la paie. Des questions ? Demandez à Alex ou à Sam.',
      'DyadeSpace usa tu ubicación solo cuando registras tu entrada o salida, para confirmar que estás en el sitio: una sola posición por registro, nunca un seguimiento continuo. Si activas el registro automático, también revisa tu ubicación en segundo plano (aproximadamente cada 15 minutos) para registrarte en las obras, y guarda tu ruta de trabajo — un punto cada 5 minutos — mientras estás registrado. No se registra nada fuera del horario. Las fotos que tomas en la aplicación las ve el equipo. Tus horas se usan para la nómina. ¿Preguntas? Pregunta a Alex o a Sam.');
  String get locationConsentTitle => _t('Location for clock-in',
      'Position pour le pointage', 'Ubicación para el registro');
  String get locationConsentBody => _t(
      'Clocking in takes one GPS reading to confirm you are at the site. It is not tracked through the day, and the reading is shared with admins for payroll. You can still use the app without it, but your clock-in will be marked unverified.',
      'Le pointage prend une seule lecture GPS pour confirmer que vous êtes sur le chantier. Votre position n’est pas suivie pendant la journée, et la lecture est partagée avec les admins pour la paie. Vous pouvez utiliser l’application sans cela, mais votre pointage sera marqué non vérifié.',
      'Al registrar tu entrada se toma una sola lectura GPS para confirmar que estás en el sitio. No se te sigue durante el día, y la lectura se comparte con los administradores para la nómina. Puedes usar la aplicación sin ella, pero tu registro quedará marcado como no verificado.');
  String get consentAllow => _t('Allow', 'Autoriser', 'Permitir');
  String get consentNotNow => _t('Not now', 'Pas maintenant', 'Ahora no');

  // ---- Auto clock-in at sites (opt-in, background location) ----
  String get autoClockInTitle => _t('Auto clock-in at sites',
      'Pointage automatique aux chantiers', 'Registro automático en las obras');
  String get autoClockInSubtitle => _t(
      'Arriving at a site clocks you in, leaving clocks you out. Needs location access "Always".',
      'Arriver sur un chantier vous pointe, partir vous sort. Nécessite l’accès à la position « Toujours ».',
      'Llegar a una obra registra tu entrada; salir, tu salida. Necesita acceso a la ubicación «Siempre».');
  String get autoClockConsentTitle => _t(
      'Background location for auto clock-in',
      'Position en arrière-plan pour le pointage automatique',
      'Ubicación en segundo plano para el registro automático');
  String get autoClockConsentBody => _t(
      'With auto clock-in on, DyadeSpace checks your location in the background (about every 15 minutes) to clock you in when you arrive at a site and out when you leave, and saves your work route — one point every 5 minutes — while you are clocked in. Nothing is recorded when you are off the clock. Entries created this way are marked "Auto", and one shorter than 10 minutes is deleted. You can turn it off anytime in Settings.',
      'Avec le pointage automatique, DyadeSpace vérifie votre position en arrière-plan (environ toutes les 15 minutes) pour vous pointer à l’arrivée sur un chantier et vous sortir au départ, et enregistre votre trajet de travail — un point toutes les 5 minutes — pendant que vous êtes pointé. Rien n’est enregistré hors des heures de travail. Les pointages ainsi créés sont marqués « Auto », et un pointage de moins de 10 minutes est supprimé. Vous pouvez le désactiver à tout moment dans Réglages.',
      'Con el registro automático, DyadeSpace revisa tu ubicación en segundo plano (aproximadamente cada 15 minutos) para registrar tu entrada al llegar a una obra y tu salida al irte, y guarda tu ruta de trabajo — un punto cada 5 minutos — mientras estás registrado. No se registra nada fuera del horario. Las entradas creadas así se marcan «Auto» y una de menos de 10 minutos se elimina. Puedes desactivarlo cuando quieras en Ajustes.');
  String get autoClockPermissionDenied => _t(
      'Auto clock-in needs location set to "Always". Turn it on in your phone Settings, then try again.',
      'Le pointage automatique exige la position « Toujours ». Activez-la dans les Réglages du téléphone, puis réessayez.',
      'El registro automático necesita la ubicación en «Siempre». Actívala en los Ajustes del teléfono y vuelve a intentarlo.');
  String get autoClockEnabled => _t(
      'Auto clock-in on — arriving at a site will clock you in.',
      'Pointage automatique activé — arriver sur un chantier vous pointera.',
      'Registro automático activado: llegar a una obra registrará tu entrada.');
  String get autoClockDisabled => _t('Auto clock-in off.',
      'Pointage automatique désactivé.', 'Registro automático desactivado.');
  String get routeTrail =>
      _t('Work route', 'Trajet de travail', 'Ruta de trabajo');

  String get eodEmailUnavailable => _t(
      'Email reports need the Trigger Email extension installed. Ask an admin to set it up.',
      'Les rapports par courriel nécessitent l’extension Trigger Email. Demandez à un admin de l’installer.',
      'Los informes por correo necesitan la extensión Trigger Email instalada. Pide a un administrador que la configure.');
  String get sendFailedKept => _t(
      'Could not send. Your message is still here.',
      'Envoi impossible. Votre message est toujours là.',
      'No se pudo enviar. Tu mensaje sigue aquí.');
  String get videoLoadError => _t('This video could not be played.',
      'Cette vidéo n’a pas pu être lue.', 'No se pudo reproducir este video.');
  String get reportFailed => _t(
      'Could not generate the report. Try again.',
      'Le rapport n’a pas pu être généré. Réessayez.',
      'No se pudo generar el informe. Inténtalo de nuevo.');
  String get deactivateUser =>
      _t('Deactivate user', 'Désactiver l’utilisateur', 'Desactivar usuario');
  String get confirmDeactivate => _t(
      'Deactivate this user? They will be signed out and cannot sign back in.',
      'Désactiver cet utilisateur ? Il sera déconnecté et ne pourra plus se connecter.',
      '¿Desactivar este usuario? Se cerrará su sesión y no podrá volver a entrar.');
  String get userDeactivated =>
      _t('User deactivated.', 'Utilisateur désactivé.', 'Usuario desactivado.');
  String get deactivateFailed => _t(
      'Could not deactivate this user. Try again.',
      'Impossible de désactiver cet utilisateur. Réessayez.',
      'No se pudo desactivar este usuario. Inténtalo de nuevo.');

  // --- Privacy policy + self-service account deletion ---
  String get privacyPolicy => _t('Privacy policy',
      'Politique de confidentialité', 'Política de privacidad');
  String get formerMember => _t('Former member', 'Ancien membre', 'Ex miembro');
  String get deleteMyAccount =>
      _t('Delete my account', 'Supprimer mon compte', 'Eliminar mi cuenta');
  String get deleteAccountTitle => _t('Delete your account?',
      'Supprimer votre compte ?', '¿Eliminar tu cuenta?');
  String get deleteAccountBody => _t(
      'This permanently deletes your sign-in, your profile (name, email, photo) and your notifications. Your clock-in history is kept — it is a payroll record — and so are the tasks and chat messages you shared with the crew, but your name on them will show as "Former member". This cannot be undone.',
      'Ceci supprime définitivement votre connexion, votre profil (nom, courriel, photo) et vos notifications. Votre historique de pointage est conservé — c’est un registre de paie — ainsi que les tâches et les messages partagés avec l’équipe, mais votre nom y apparaîtra comme « Ancien membre ». Cette action est irréversible.',
      'Esto elimina permanentemente tu inicio de sesión, tu perfil (nombre, correo, foto) y tus notificaciones. Tu historial de registro se conserva — es un registro de nómina — igual que las tareas y los mensajes que compartiste con el equipo, pero tu nombre en ellos aparecerá como «Ex miembro». No se puede deshacer.');
  String get accountDeleted => _t('Your account was deleted.',
      'Votre compte a été supprimé.', 'Tu cuenta fue eliminada.');
  String get deleteAccountFailed => _t(
      'Could not delete your account. Try again.',
      'Impossible de supprimer votre compte. Réessayez.',
      'No se pudo eliminar tu cuenta. Inténtalo de nuevo.');

  // ---- Audit fixes (Nov 21, 2026): Area D auth / account ----
  String get createAccount => _t(
      'Create account', 'Créer un compte', 'Crear cuenta');
  String get confirmPassword => _t(
      'Confirm password', 'Confirmer le mot de passe', 'Confirmar contraseña');
  String get nameRequired => _t(
      'Enter your name first.',
      'Entrez d’abord votre nom.',
      'Escribe tu nombre primero.');
  String get passwordsDoNotMatch => _t(
      'The passwords do not match. Check them and try again.',
      'Les mots de passe ne correspondent pas. Vérifiez-les et réessayez.',
      'Las contraseñas no coinciden. Revísalas e inténtalo de nuevo.');
  String get noInvite => _t(
      'No invite found for this email. Ask Sam or Alex to invite you first.',
      'Aucune invitation trouvée pour ce courriel. Demandez d’abord à Sam ou Alex de vous inviter.',
      'No se encontró ninguna invitación para este correo. Pide primero a Sam o Alex que te invite.');
  String get accountDeactivatedTitle => _t(
      'Your account was deactivated',
      'Votre compte a été désactivé',
      'Tu cuenta fue desactivada');
  String get accountDeactivatedBody => _t(
      'Your account was deactivated by an admin, so you can no longer use DyadeSpace. Contact Sam or Alex if you think this is a mistake.',
      'Votre compte a été désactivé par un administrateur, vous ne pouvez donc plus utiliser DyadeSpace. Contactez Sam ou Alex si vous pensez qu’il s’agit d’une erreur.',
      'Un administrador desactivó tu cuenta, por lo que ya no puedes usar DyadeSpace. Contacta con Sam o Alex si crees que es un error.');
  String get profileLoadFailed => _t(
      'Could not load your profile. Check your connection and try again.',
      'Impossible de charger votre profil. Vérifiez votre connexion et réessayez.',
      'No se pudo cargar tu perfil. Revisa tu conexión e inténtalo de nuevo.');
  String get settingsSaveFailed => _t(
      'Could not save that setting. Try again.',
      'Impossible d’enregistrer ce réglage. Réessayez.',
      'No se pudo guardar ese ajuste. Inténtalo de nuevo.');
  String get adminInviteRequiresAdmin => _t(
      'Only an admin can invite an admin account.',
      'Seul un administrateur peut inviter un compte administrateur.',
      'Solo un administrador puede invitar una cuenta de administrador.');
  String bulkInviteOverCap(int n) => _t(
      n == 1
          ? '1 email was over the 100-invite limit and was not invited. Run another batch for it.'
          : '$n emails were over the 100-invite limit and were not invited. Run another batch for them.',
      n == 1
          ? '1 courriel dépassait la limite de 100 invitations et n’a pas été invité. Lancez un autre lot pour celui-ci.'
          : '$n courriels dépassaient la limite de 100 invitations et n’ont pas été invités. Lancez un autre lot pour ceux-ci.',
      n == 1
          ? '1 correo superó el límite de 100 invitaciones y no fue invitado. Ejecuta otro lote para él.'
          : '$n correos superaron el límite de 100 invitaciones y no fueron invitados. Ejecuta otro lote para ellos.');
}
