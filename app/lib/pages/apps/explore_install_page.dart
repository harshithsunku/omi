import 'package:flutter/material.dart';
import 'package:omi/backend/schema/app.dart';
import 'package:omi/pages/apps/providers/add_app_provider.dart';
import 'package:omi/pages/apps/widgets/app_section_card.dart';
import 'package:omi/pages/apps/widgets/filter_sheet.dart';
import 'package:omi/pages/apps/list_item.dart';
import 'package:omi/providers/app_provider.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/utils/other/debouncer.dart';
import 'package:provider/provider.dart';

import 'widgets/create_options_sheet.dart';

String filterValueToString(dynamic value) {
  if (value.runtimeType == String) {
    return value;
  } else if (value.runtimeType == Category) {
    return (value as Category).title;
  } else if (value.runtimeType == AppCapability) {
    return (value as AppCapability).title;
  }
  return '';
}

class ExploreInstallPage extends StatefulWidget {
  const ExploreInstallPage({super.key});

  @override
  State<ExploreInstallPage> createState() => _ExploreInstallPageState();
}

class _ExploreInstallPageState extends State<ExploreInstallPage> with AutomaticKeepAliveClientMixin {
  late TextEditingController searchController;
  Debouncer debouncer = Debouncer(delay: const Duration(milliseconds: 500));

  @override
  void initState() {
    searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AddAppProvider>().init();
    });
    super.initState();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<AppProvider>(builder: (context, provider, child) {
      return CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 50,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: ChoiceChip(
                      label: Row(
                        children: [
                          const Icon(
                            Icons.filter_list_alt,
                            size: 15,
                          ),
                          const SizedBox(width: 4),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6.5),
                            child: Text(
                              'Filter ',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                          provider.isFilterActive() ? Text("(${provider.filters.length})") : const SizedBox.shrink(),
                        ],
                      ),
                      selected: false,
                      showCheckmark: true,
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onSelected: (bool selected) {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          builder: (context) => const FilterBottomSheet(),
                        ).whenComplete(() {
                          context.read<AppProvider>().filterApps();
                        });
                      },
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  provider.isFilterActive()
                      ? Expanded(
                          child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (ctx, idx) {
                            return ChoiceChip(
                              labelPadding: const EdgeInsets.only(left: 8, right: 4),
                              label: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.5),
                                    child: Text(
                                      filterValueToString(provider.filters.values.elementAt(idx)),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.close,
                                    size: 15,
                                  ),
                                ],
                              ),
                              selected: false,
                              showCheckmark: true,
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onSelected: (bool selected) {
                                provider.removeFilter(provider.filters.keys.elementAt(idx));
                              },
                            );
                          },
                          separatorBuilder: (ctx, idx) {
                            return const SizedBox(
                              width: 10,
                            );
                          },
                          itemCount: provider.filters.length,
                        ))
                      : SizedBox(
                          width: MediaQuery.sizeOf(context).width * 0.71,
                          height: 40,
                          child: TextFormField(
                            controller: searchController,
                            focusNode: context.read<HomeProvider>().appsSearchFieldFocusNode,
                            onChanged: (value) {
                              debouncer.run(() {
                                provider.searchApps(value);
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Search Apps',
                              hintStyle: const TextStyle(color: Colors.white),
                              filled: true,
                              fillColor: Colors.grey[800],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: provider.isSearchActive()
                                  ? GestureDetector(
                                      onTap: () {
                                        context.read<HomeProvider>().appsSearchFieldFocusNode.unfocus();
                                        provider.searchApps('');
                                        searchController.clear();
                                      },
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
              child: SizedBox(
            height: 20,
          )),
          SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () async {
                // routeToPage(context, SocialHandleScreen());
                showModalBottomSheet(
                  context: context,
                  builder: (context) => const CreateOptionsSheet(),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12.0),
                margin: const EdgeInsets.only(left: 12.0, right: 12.0, top: 2, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: const ListTile(
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Create your own',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          !provider.isFilterActive() && !provider.isSearchActive()
              ? const SliverToBoxAdapter(child: SizedBox.shrink())
              : Consumer<AppProvider>(
                  builder: (context, provider, child) {
                    if (provider.filteredApps.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.28),
                          child: const Text(
                            'No apps found',
                            style: TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.only(bottom: 64),
                      sliver: SliverList.separated(
                        itemCount: provider.filteredApps.length,
                        itemBuilder: (context, index) {
                          final originalIndex =
                              provider.apps.indexWhere((app) => app.id == provider.filteredApps[index].id);
                          return AppListItem(
                            app: provider.filteredApps[index],
                            index: originalIndex,
                          );
                        },
                        separatorBuilder: (context, index) {
                          return const SizedBox(height: 8);
                        },
                      ),
                    );
                  },
                ),
          !provider.isFilterActive() && !provider.isSearchActive()
              ? SliverToBoxAdapter(
                  child: AppSectionCard(
                    title: 'Popular Apps',
                    apps: context
                        .read<AppProvider>()
                        .apps
                        .where((p) => (p.installs > 50 && (p.ratingAvg ?? 0.0) > 4.0))
                        .take(6)
                        .toList(),
                  ),
                )
              : const SliverToBoxAdapter(child: SizedBox.shrink()),
          !provider.isFilterActive() && !provider.isSearchActive()
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(left: 12.0, top: 18, bottom: 0),
                    child: Text('All Apps', style: TextStyle(fontSize: 18)),
                  ),
                )
              : const SliverToBoxAdapter(child: SizedBox.shrink()),
          !provider.isFilterActive() && !provider.isSearchActive()
              ? Selector<AppProvider, List<App>>(
                  selector: (context, provider) => provider.apps,
                  builder: (context, apps, child) {
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return AppListItem(
                            app: apps[index],
                            index: index,
                          );
                        },
                        childCount: apps.length,
                      ),
                    );
                  },
                )
              : const SliverToBoxAdapter(child: SizedBox.shrink()),
        ],
      );
    });
  }

  @override
  bool get wantKeepAlive => true;
}
