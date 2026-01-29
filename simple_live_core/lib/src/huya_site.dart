import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';

class HuyaSite extends LiveSite {
  @override
  String get id => "huya";

  @override
  String get name => "虎牙直播";

  @override
  List<LiveCategory> get categories => [];

  @override
  Future<List<LiveRoomItem>> getCategoryRooms(
      LiveCategory category, int page) async {
    return [];
  }

  @override
  Future<List<LiveRoomItem>> searchRooms(String keyword, int page) async {
    var url =
        "https://search.cdn.huya.com/?m=Search&do=getSearchContent&q=${Uri.encodeComponent(keyword)}&uid=0&v=4&typ=-5&livestate=0&rows=20&start=${(page - 1) * 20}";
    var res = await HttpClient.instance.get(url);
    var json = jsonDecode(res.body);
    var docs = json["response"]?["3"]?["docs"] ?? [];
    List<LiveRoomItem> list = [];
    for (var item in docs) {
      var cover = item["game_screenshot"] ??
          item["game_avatarUrl180"] ??
          item["game_avatarUrl52"] ??
          "";
      list.add(LiveRoomItem(
        roomId: item["game_privateHost"].toString(),
        title: item["game_introduction"].toString(),
        cover: cover.toString(),
        userName: item["game_nick"].toString(),
        online:
            int.tryParse(item["game_total_count"].toString()) ?? 0,
      ));
    }
    return list;
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(
      String keyword, int page) async {
    var url =
        "https://search.cdn.huya.com/?m=Search&do=getSearchContent&q=${Uri.encodeComponent(keyword)}&uid=0&v=4&typ=1&rows=20&start=${(page - 1) * 20}";
    var res = await HttpClient.instance.get(url);
    var json = jsonDecode(res.body);
    var docs = json["response"]?["1"]?["docs"] ?? [];
    List<LiveAnchorItem> list = [];
    for (var item in docs) {
      list.add(LiveAnchorItem(
        roomId: item["game_privateHost"]?.toString() ??
            item["yyid"].toString(),
        avatar: item["game_avatarUrl180"].toString(),
        userName: item["game_nick"].toString(),
        liveStatus: item["gameLiveOn"] == true,
      ));
    }
    return list;
  }

  @override
  Future<LiveRoomDetail> getRoomDetail(String roomId) async {
    var url =
        "https://mp.huya.com/cache.php?m=Live&do=profileRoom&roomid=$roomId";
    var res = await HttpClient.instance.get(url);
    var json = jsonDecode(res.body);
    var data = json["data"] ?? {};
    var liveInfo = data["liveData"] ?? {};
    var profile = data["profile"] ?? {};
    return LiveRoomDetail(
      roomId: roomId,
      title: liveInfo["introduction"].toString(),
      cover: liveInfo["screenshot"].toString(),
      userName: profile["nick"].toString(),
      online:
          int.tryParse(liveInfo["totalCount"].toString()) ?? 0,
      status: liveInfo["liveStatus"] == "ON",
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities(
      LiveRoomDetail detail) async {
    return [
      LivePlayQuality(
          quality: "原画", sort: 0, data: "original")
    ];
  }

  @override
  Future<List<LivePlayUrl>> getPlayUrls(
      LiveRoomDetail detail, LivePlayQuality quality) async {
    var roomId = detail.roomId;
    var infoUrl =
        "https://m.huya.com/$roomId";
    var res = await HttpClient.instance.get(infoUrl);
    var html = res.body;
    var reg = RegExp(r'window\.HNF_GLOBAL_INIT = (.*);');
    var match = reg.firstMatch(html);
    if (match == null) return [];
    var json = jsonDecode(match.group(1)!);
    var streamInfo = json["roomInfo"]["tLiveInfo"];
    var stream = streamInfo["tLiveStreamInfo"]["vStreamInfo"]["value"][0];
    var flv = stream["sFlvUrl"];
    var streamName = stream["sStreamName"];
    var anticode = stream["sFlvAntiCode"];
    var presenterUid =
        streamInfo["lUid"] ?? streamInfo["lYyid"] ?? 0;
    var wsTime =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var seqId = wsTime + presenterUid;
    var fm = Uri.decodeComponent(anticode.split("fm=")[1].split("&")[0]);
    var hash =
        md5.convert(utf8.encode("$seqId|$streamName|$wsTime")).toString();
    var wsSecret =
        md5.convert(utf8.encode("$hash$fm")).toString();
    var playUrl =
        "$flv/$streamName.flv?wsSecret=$wsSecret&wsTime=${wsTime.toRadixString(16)}&seqid=$seqId";
    return [
      LivePlayUrl(url: playUrl)
    ];
  }
}
