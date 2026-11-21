// The DyadeSpace privacy policy, in the app's three languages.
// Kept apart from app_strings.dart because it is long-form
// text, not UI labels. The policy is shown in-app (Settings
// and the sign-in screen) and on the public /privacy route,
// which is also the deletion-request link the app stores ask
// for: it states the in-app deletion path (Settings → Account
// → Delete my account). Contact goes through the company
// domain dyademanagement.com — no personal email is published.

/// One titled section of the policy.
class PrivacySection {
  final String title;
  final String body;
  const PrivacySection(this.title, this.body);
}

/// Sections for [lang] ('en', 'fr' or 'es'; anything else
/// falls back to English).
List<PrivacySection> privacyPolicySections(String lang) {
  String t(String en, String fr, String es) =>
      lang == 'fr' ? fr : (lang == 'es' ? es : en);
  return [
    PrivacySection(
      t('Who we are', 'Qui nous sommes', 'Quiénes somos'),
      t(
        'DyadeSpace is the crew app of Dyade Management, a renovation company in Montreal, Quebec. It coordinates work sites, hours and messages for the company’s crew. If you have a question about your personal information, contact Dyade Management through dyademanagement.com.',
        'DyadeSpace est l’application d’équipe de Dyade Management, une entreprise de rénovation à Montréal, au Québec. Elle coordonne les chantiers, les heures et les messages de l’équipe. Pour toute question sur vos renseignements personnels, contactez Dyade Management via dyademanagement.com.',
        'DyadeSpace es la aplicación del equipo de Dyade Management, una empresa de renovación en Montreal, Quebec. Coordina las obras, las horas y los mensajes del equipo. Si tienes una pregunta sobre tu información personal, contacta a Dyade Management a través de dyademanagement.com.',
      ),
    ),
    PrivacySection(
      t('What we collect', 'Ce que nous recueillons',
          'Qué recopilamos'),
      t(
        'Account: your name, email address, role (admin, manager, worker or delivery) and profile photo if you add one. Location: one GPS reading when you clock in or out, to confirm you are at the site. If you turn on auto clock-in, your location is also checked in the background (about every 15 minutes) and your work route is saved — one point every 5 minutes — only while you are clocked in. Messages: your chat messages, photos, videos and voice notes, and the photos you attach to tasks and delivery stops. Hours: your clock-in and clock-out times, and the hours computed from them. Diagnostics: anonymous crash reports that help fix bugs.',
        'Compte : votre nom, votre adresse courriel, votre rôle (admin, gestionnaire, travailleur ou livraison) et votre photo de profil si vous en ajoutez une. Position : une seule lecture GPS quand vous pointez à l’arrivée ou au départ, pour confirmer que vous êtes sur le chantier. Si vous activez le pointage automatique, votre position est aussi vérifiée en arrière-plan (environ toutes les 15 minutes) et votre trajet de travail est enregistré — un point toutes les 5 minutes — seulement pendant que vous êtes pointé. Messages : vos messages de discussion, photos, vidéos et notes vocales, ainsi que les photos jointes aux tâches et aux arrêts de livraison. Heures : vos heures de pointage et les heures calculées à partir de celles-ci. Diagnostic : des rapports d’erreur anonymes qui aident à corriger les bogues.',
        'Cuenta: tu nombre, tu correo electrónico, tu rol (administrador, gerente, trabajador o reparto) y tu foto de perfil si agregas una. Ubicación: una sola lectura GPS cuando registras tu entrada o salida, para confirmar que estás en el sitio. Si activas el registro automático, tu ubicación también se revisa en segundo plano (aproximadamente cada 15 minutos) y tu ruta de trabajo se guarda — un punto cada 5 minutos — solo mientras estás registrado. Mensajes: tus mensajes de chat, fotos, videos y notas de voz, y las fotos que adjuntas a las tareas y a las paradas de entrega. Horas: tus horas de registro y las horas calculadas a partir de ellas. Diagnóstico: informes de errores anónimos que ayudan a corregir fallos.',
      ),
    ),
    PrivacySection(
      t('Why we use it', 'Pourquoi nous l’utilisons', 'Para qué lo usamos'),
      t(
        'To run the crew: assign tasks, see who is on which site, and message each other. To pay people: your hours are the payroll record. To prove the work: photos on tasks and delivery stops. Location is used only to confirm clock-ins at sites and, when auto clock-in is on, to clock you in and out — never to follow you outside work.',
        'Pour faire fonctionner l’équipe : attribuer les tâches, voir qui est sur quel chantier et échanger des messages. Pour payer les gens : vos heures sont le registre de paie. Pour prouver le travail : les photos sur les tâches et les arrêts de livraison. La position sert uniquement à confirmer les pointages sur les chantiers et, quand le pointage automatique est activé, à vous pointer — jamais à vous suivre en dehors du travail.',
        'Para organizar al equipo: asignar tareas, ver quién está en cada obra y comunicarse. Para pagar: tus horas son el registro de nómina. Para demostrar el trabajo: las fotos en las tareas y en las paradas de entrega. La ubicación solo se usa para confirmar los registros en las obras y, cuando el registro automático está activado, para registrarte — nunca para seguirte fuera del trabajo.',
      ),
    ),
    PrivacySection(
      t('Where your data lives', 'Où vos données sont conservées',
          'Dónde viven tus datos'),
      t(
        'Your data is stored with Google Firebase, in the United States (Firestore region nam5, Cloud Functions region us-central1). That means your information may be processed in the US. We do not sell your data, show ads, or share it with advertisers.',
        'Vos données sont conservées chez Google Firebase, aux États-Unis (région Firestore nam5, région Cloud Functions us-central1). Vos renseignements peuvent donc être traités aux États-Unis. Nous ne vendons pas vos données, n’affichons pas de publicité et ne les partageons pas avec des annonceurs.',
        'Tus datos se guardan con Google Firebase, en los Estados Unidos (región de Firestore nam5, región de Cloud Functions us-central1). Eso significa que tu información puede procesarse en EE. UU. No vendemos tus datos, no mostramos anuncios ni los compartimos con anunciantes.',
      ),
    ),
    PrivacySection(
      t('Who can see it', 'Qui peut les voir', 'Quién puede verlos'),
      t(
        'Admins and managers of your company can see crew profiles, tasks, hours and messages, because they run the work and the payroll. Other crew members see the tasks, photos and messages they need for their own work. Nobody outside the company can see your data.',
        'Les administrateurs et gestionnaires de votre entreprise peuvent voir les profils, les tâches, les heures et les messages de l’équipe, parce qu’ils gèrent le travail et la paie. Les autres membres de l’équipe voient les tâches, les photos et les messages nécessaires à leur propre travail. Personne à l’extérieur de l’entreprise ne peut voir vos données.',
        'Los administradores y gerentes de tu empresa pueden ver los perfiles, las tareas, las horas y los mensajes del equipo, porque gestionan el trabajo y la nómina. Los demás miembros del equipo ven las tareas, las fotos y los mensajes necesarios para su propio trabajo. Nadie fuera de la empresa puede ver tus datos.',
      ),
    ),
    PrivacySection(
      t('How long we keep it', 'Combien de temps nous les gardons',
          'Cuánto tiempo los guardamos'),
      t(
        'Your clock-in history is a payroll record and is kept. Tasks and chat messages are shared records of the crew’s work and are kept too. When you delete your account, your sign-in, your profile and your notifications are deleted, and your profile photo is deleted as well.',
        'Votre historique de pointage est un registre de paie et est conservé. Les tâches et les messages sont des registres partagés du travail de l’équipe et sont conservés aussi. Quand vous supprimez votre compte, votre connexion, votre profil et vos notifications sont supprimés, ainsi que votre photo de profil.',
        'Tu historial de registro es un registro de nómina y se conserva. Las tareas y los mensajes son registros compartidos del trabajo del equipo y también se conservan. Cuando eliminas tu cuenta, se eliminan tu inicio de sesión, tu perfil y tus notificaciones, además de tu foto de perfil.',
      ),
    ),
    PrivacySection(
      t('Deleting your account', 'Supprimer votre compte',
          'Eliminar tu cuenta'),
      t(
        'You can delete your account yourself at any time: Settings → Account → Delete my account. Deleting removes your sign-in, your profile (name, email, photo) and your notifications. Your clock-in history is kept as a payroll record, and the tasks and chat messages you shared stay, but your name on them will show as “Former member”. Deletion cannot be undone.',
        'Vous pouvez supprimer votre compte vous-même à tout moment : Réglages → Compte → Supprimer mon compte. La suppression retire votre connexion, votre profil (nom, courriel, photo) et vos notifications. Votre historique de pointage est conservé comme registre de paie, et les tâches et les messages partagés restent, mais votre nom y apparaîtra comme « Ancien membre ». La suppression est irréversible.',
        'Puedes eliminar tu cuenta cuando quieras: Ajustes → Cuenta → Eliminar mi cuenta. Al eliminarla se quitan tu inicio de sesión, tu perfil (nombre, correo, foto) y tus notificaciones. Tu historial de registro se conserva como registro de nómina, y las tareas y los mensajes compartidos permanecen, pero tu nombre en ellos aparecerá como «Ex miembro». La eliminación no se puede deshacer.',
      ),
    ),
    PrivacySection(
      t('Your rights', 'Vos droits', 'Tus derechos'),
      t(
        'Under Québec’s Law 25, you can ask to see the personal information we hold about you, to correct it, and to have it deleted (except payroll records we must keep). You can also withdraw your consent for location at any time: turn off auto clock-in in Settings, or clock in without location — that entry is then marked unverified. To make a request, contact Dyade Management through dyademanagement.com.',
        'En vertu de la Loi 25 du Québec, vous pouvez demander à voir les renseignements personnels que nous détenons sur vous, à les corriger et à les faire supprimer (sauf les registres de paie que nous devons conserver). Vous pouvez aussi retirer votre consentement à la localisation à tout moment : désactivez le pointage automatique dans Réglages, ou pointez sans la position — ce pointage sera alors marqué non vérifié. Pour faire une demande, contactez Dyade Management via dyademanagement.com.',
        'Según la Ley 25 de Quebec, puedes pedir ver la información personal que tenemos sobre ti, corregirla y que se elimine (excepto los registros de nómina que debemos conservar). También puedes retirar tu consentimiento de ubicación en cualquier momento: desactiva el registro automático en Ajustes, o registra sin ubicación — ese registro quedará marcado como no verificado. Para hacer una solicitud, contacta a Dyade Management a través de dyademanagement.com.',
      ),
    ),
    PrivacySection(
      t('Changes to this policy', 'Modifications de cette politique',
          'Cambios a esta política'),
      t(
        'If this policy changes, the new version will be published here in the app. The date of the last update is shown below.',
        'Si cette politique change, la nouvelle version sera publiée ici, dans l’application. La date de la dernière mise à jour est indiquée ci-dessous.',
        'Si esta política cambia, la nueva versión se publicará aquí, en la aplicación. La fecha de la última actualización se muestra abajo.',
      ),
    ),
  ];
}

/// "Last updated" line, in the policy's language.
String privacyPolicyUpdated(String lang) {
  String t(String en, String fr, String es) =>
      lang == 'fr' ? fr : (lang == 'es' ? es : en);
  return t(
    'Last updated: November 16, 2026.',
    'Dernière mise à jour : 16 novembre 2026.',
    'Última actualización: 16 de noviembre de 2026.',
  );
}
