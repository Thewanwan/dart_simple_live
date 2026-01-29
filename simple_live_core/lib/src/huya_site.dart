import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';

class HuyaSite implements LiveSite {
  @override
  String get id => 'huya';

  @override
  String get name => '虎牙直播';

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    return LiveCategoryResult(
      hasMore: false,
      rooms: [],
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    final url =
        'https://search.cdn.huya.com/?m=Search&do=getSearchContent&q=$keyword&uid=0&v=4&typ=-5&livestate=0&rows=20&start=${(page - 1) * 20}';

    final res = await HttpClient.instance.getJson(url);
    final docs = res['response']?['1']?['docs'] ?? [];

    final rooms = <LiveRoomItem>[];

    for (final item in docs) {
      final roomId = item['room_id']?.toString();
      if (roomId == null || roomId.isEmpty) continue;

      rooms.add(
        LiveRoomItem(
          roomId: roomId,
          title: item['live_intro'] ?? '',
          cover: item['game_avatarUrl180'] ?? '',
          userName: item['game_nick'] ?? '',
          online: item['game_activityCount'] ?? 0,
          siteId: id,
        ),
      );
    }

    return LiveSearchRoomResult(
      hasMore: rooms.length == 20,
      rooms: rooms,
    );
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    return LiveSearchAnchorResult(
      hasMore: false,
      anchors: <LiveAnchorItem>[],
    );
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    final url = 'https://www.huya.com/$roomId';
    final text = await HttpClient.instance.getText(url);

    final uidMatch =
        RegExp(r'"uid"\s*:\s*(\d+)').firstMatch(text);
    final uid = uidMatch?.group(1) ?? '';

    return LiveRoomDetail(
      roomId: roomId,
      title: '',
      userName: '',
      userAvatar: '',
      online: 0,
      status: true,
      siteId: id,
      data: {'uid': uid},
    );
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required String roomId,
    String? line,
  }) async {
    final infoUrl =
        'https://mp.huya.com/cache.php?m=Live&do=profileRoom&roomid=$roomId';
    final res = await HttpClient.instance.getJson(infoUrl);

    final stream = res['data']?['stream']?['baseSteamInfoList']?[0];
    final url = stream?['sFlvUrl'];
    final streamName = stream?['sStreamName'];
    final suffix = stream?['sFlvUrlSuffix'];
    final antiCode = stream?['sFlvAntiCode'];

    final playUrl =
        '$url/$streamName.$suffix?$antiCode';

    final sign = md5
        .convert(utf8.encode(playUrl))
        .toString();

    return LivePlayUrl(
      playUrl: playUrl,
      sign: sign,
    );
  }
}
