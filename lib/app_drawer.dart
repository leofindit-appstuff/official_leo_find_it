//For the hamburger menu feature
import 'package:flutter/material.dart';
import 'filters_page.dart';
import 'reports_page.dart';

class AppDrawer extends StatelessWidget {
  final GlobalKey? filtersTileKey;
  final GlobalKey? reportsTileKey;

  const AppDrawer({
    super.key,
    this.filtersTileKey,
    this.reportsTileKey,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Text(
                "Other options",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              key: filtersTileKey,
              leading: const Icon(Icons.tune),
              title: const Text("Filters"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FiltersPage()),
                );
              },
            ),
            ListTile(
              key: reportsTileKey,
              leading: const Icon(Icons.description_outlined),
              title: const Text("Reports"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
