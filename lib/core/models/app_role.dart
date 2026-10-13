enum AppRole { citizen, municipalAdmin, contractor }

extension AppRoleText on AppRole {
  String get label => switch (this) {
        AppRole.citizen => 'Citizen',
        AppRole.municipalAdmin => 'Municipal Admin',
        AppRole.contractor => 'Contractor',
      };

  String get tagline => switch (this) {
        AppRole.citizen => 'Report issues, support neighbours, track progress.',
        AppRole.municipalAdmin =>
          'Verify reports, set priorities, assign and inspect work.',
        AppRole.contractor =>
          'Bid on jobs, log progress, submit before/after evidence.',
      };
}

class Actor {
  const Actor({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final AppRole role;

  static const demoCitizen =
      Actor(id: 'cit-ayesha', name: 'Ayesha Rahman', role: AppRole.citizen);
  static const demoAdmin = Actor(
      id: 'adm-ward4', name: 'Ward 4 Officer', role: AppRole.municipalAdmin);
  static const demoContractor = Actor(
      id: 'ctr-metro', name: 'Metro Roads & Works', role: AppRole.contractor);

  static Actor demoFor(AppRole role) => switch (role) {
        AppRole.citizen => demoCitizen,
        AppRole.municipalAdmin => demoAdmin,
        AppRole.contractor => demoContractor,
      };
}
