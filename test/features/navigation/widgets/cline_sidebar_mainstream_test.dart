import 'package:conduit/features/navigation/widgets/sidebar_tab_registry.dart';
import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mainstream sliding navigation retains Cline fourth and resolves its route', () {
    final tabs=visibleSidebarTabIds(const SidebarTabAvailability(
      hermesOnly:false,hasOpenWebUi:true,hermesEnabled:false,
      notesEnabled:true,terminalEnabled:true,channelsEnabled:true,
    ));
    expect(tabs[3],SidebarTabId.cline);
    expect(sidebarTabDescriptor(SidebarTabId.cline).location,Routes.clineSidebar);
    expect(sidebarTabDescriptor(SidebarTabId.cline).location,isNot(Routes.clineWorkspace));
    expect(sidebarTabForLocation(Routes.clineSidebar),SidebarTabId.cline);
    expect(sidebarTabForLocation('${Routes.clineSidebar}/fixture'),SidebarTabId.cline);
    expect(visibleSidebarTabIds(const SidebarTabAvailability(
      hermesOnly:true,hasOpenWebUi:false,hermesEnabled:true,
      notesEnabled:false,terminalEnabled:false,channelsEnabled:false,
    )),isNot(contains(SidebarTabId.cline)));
  });
}
