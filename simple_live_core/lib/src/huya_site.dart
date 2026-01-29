import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';

class HuyaSite implements LiveSite {
  @override
  String id = 'huya';

  @override
  String name = '虎牙直播';

  @override
  LiveDanmaku getDanmaku() => LiveDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async => [];

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category, {int page = 1}) async {
    return LiveCategoryResult(hasMore: false, items: []);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    return LiveCategoryResult(hasMore: false, items: []);
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async {
    final url = 'https://search.cdn.huya.com/?m=Search&do=getSearchContent&q=$keyword&uid=0&v=4&typ=-5&livestate=0&rows=20&start=${(page - 1) * 20}';
    final res = await HttpClient.instance.getJson(url);
    final docs = res['response']?['1']?['docs'] ?? [];
    final items = <LiveRoomItem>[];

    for (final item in docs) {
      final rId = item['room_id']?.toString() ?? "";
      if (rId.isEmpty) continue;
      items.add(LiveRoomItem(
        roomId: rId,
        title: item['live_intro'] ?? '',
        cover: item['game_avatarUrl180'] ?? '',
        userName: item['game_nick'] ?? '',
        online: item['game_activityCount'] ?? 0,
      ));
    }
    return LiveSearchRoomResult(hasMore: items.length == 20, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async {
    return LiveSearchAnchorResult(hasMore: false, items: []);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    return LiveRoomDetail(
      roomId: roomId,
      title: '虎牙直播',
      userName: '未知主播',
      userAvatar: '',
      online: 0,
      status: true,
      cover: '',
      url: 'https://www.huya.com/$roomId',
      data: {},
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoomDetail detail}) async {
    return [LivePlayQuality(quality: "原画", data: detail.roomId)];
  }

  @override
  Future<LivePlayUrl> getPlayUrls({required LiveRoomDetail detail, required LivePlayQuality quality}) async {
    final roomId = quality.data as String;
    final infoUrl = 'https://mp.huya.com/cache.php?m=Live&do=profileRoom&roomid=$roomId';
    final res = await HttpClient.instance.getJson(infoUrl);
    final stream = res['data']?['stream']?['baseSteamInfoList']?[0];
    final playUrl = '${stream?['sFlvUrl']}/${stream?['sStreamName']}.${stream?['sFlvUrlSuffix']}?${stream?['sFlvAntiCode']}';

    return LivePlayUrl(urls: [playUrl]);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async => true;

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) async => [];
}
