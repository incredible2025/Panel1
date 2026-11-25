/// Increment only when the declaration changes substantively, not each release.
const contentDeclarationVersion = 1;
const contentDeclarationSections = <(String, String)>[
  (
    'Player software only',
    'This app is a media player. The app developer develops and maintains the software only. '
        'The developer does not provide, host, sell or distribute television channels, live streams, films, series or other media content.',
  ),
  (
    'Content comes from your service provider',
    'Any content, catalogue, account, subscription or service configured in this app is supplied by the relevant third-party service provider, not the app developer. '
        'Installing or purchasing the app does not include content or grant any rights to view it.',
  ),
  (
    'Use authorised content',
    'You are responsible for ensuring you have the permissions, licences or other lawful entitlement required to access any content you use with this app. '
        'The app must not be used to access or distribute content unlawfully.',
  ),
  (
    'Content and subscription enquiries',
    'Contact your service provider about content availability, subscriptions, accounts or streaming service issues. '
        'The app developer provides support for the player software.',
  ),
];
const contentDeclarationAcknowledgement =
    'I understand that the app developer supplies the player software only and does not supply content. I will only access content I am lawfully entitled to use.';
