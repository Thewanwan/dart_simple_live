import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:crypto/crypto.dart';
import 'package:simple_live_core/src/model/tars/get_cdn_token_ex_req.dart';
import 'package:simple_live_core/src/model/tars/get_cdn_token_ex_resp.dart';
import 'package:simple_live_core/src/model/tars/huya_user_id.dart';
import 'package:tars_dart/tars/net/base_tars_http.dart';

class HuyaSite implements LiveSite {
  static const baseUrl = "https://m.huya.com/";
  final String kUserAgent =
      "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36";

  static const String HYSDK_UA =
      "HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)";

  final BaseTarsHttp tupClient = BaseTarsHttp(
    "http://wup.huya.com",
    "liveui",
    headers: {
      'Origin': baseUrl,
      'Referer': baseUrl,
      'User-Agent': HYSDK_UA,
    },
  );

  @override
  String id = "huya";
  @override
  String name = "虎牙直播";

  @override
  LiveDanmaku getDanmaku() => HuyaDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [
      LiveCategory(id: "1", name: "网游", children: []),
      LiveCategory(id: "2", name: "单机", children: []),
      LiveCategory(id: "8", name: "娱乐", children: []),
      LiveCategory(id: "3", name: "手游", children: []),
    ];
    for (var item in categories) {
      item.children.addAll(await getSubCategores(item.id));
    }
    return categories;
  }

  Future<List<LiveSubCategory>> getSubCategores(String id) async {
    var result = await HttpClient.instance.getJson(
      "https://live.cdn.huya.com/liveconfig/game/bussLive",
      queryParameters: {"bussType": id},
    );
    List<LiveSubCategory> subs = [];
    for (var item in result["data"]) {
      var gid = item["gid"] is Map
          ? item["gid"]["value"].toString().split(",").first
          : item["gid"].toString();
      subs.add(
        LiveSubCategory(
          id: gid,
          name: item["gameFullName"].toString(),
          parentId: id,
          pic: "https://huyaimg.msstatic.com/cdnimage/game/$gid-MS.jpg",
        ),
      );
    }
    return subs;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://www.huya.com/cache.php",
      queryParameters: {
        "m": "LiveList",
        "do": "getLiveListByPage",
        "gameId": category.id,
        "page": page,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["datas"]) {
      items.add(
        LiveRoomItem(
          roomId: item["profileRoom"].toString(),
          title: item["introduction"] ?? item["roomName"] ?? "",
          cover: item["screenshot"].toString(),
          userName: item["nick"].toString(),
          online:
              int.tryParse(item["totalCount"].toString()) ?? 0,
        ),
      );
    }
    return LiveCategoryResult(
      hasMore: result["data"]["page"] < result["data"]["totalPage"],
      items: items,
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://search.cdn.huya.com/",
      queryParameters: {
        "m": "Search",
        "do": "getSearchContent",
        "q": keyword,
        "v": 4,
        "typ": -5,
        "rows": 20,
        "start": (page - 1) * 20,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveRoomItem>[];

    var response = result["response"] ?? {};
    var docs =
        response["1"]?["docs"] ?? response["3"]?["docs"] ?? [];

    for (var item in docs) {
      var roomId = "0";
      if (item["room_id"] != null && item["room_id"] != 0) {
        roomId = item["room_id"].toString();
      }
      if (roomId == "0") continue;

      String cover =
          item["game_screenshot"] ??
              item["game_imgUrl"] ??
              item["cover"] ??
              "";
      if (cover.startsWith("//")) cover = "https:$cover";

      items.add(
        LiveRoomItem(
          roomId: roomId,
          title: item["game_introduction"] ??
              item["live_intro"] ??
              "",
          cover: cover,
          userName: item["game_nick"] ?? "",
          online: int.tryParse(
                  item["game_total_count"]?.toString() ??
                      item["game_activityCount"]?.toString() ??
                      "0") ??
              0,
        ),
      );
    }

    return LiveSearchRoomResult(
      hasMore:
          (response["1"]?["numFound"] ?? 0) > page * 20,
      items: items,
    );
  }

  @override
  Future<LiveRoomDetail> getRoomDetail(
      {required String roomId}) async {
    String realRoomId = roomId;
    if (roomId.length >= 10) {
      try {
        var html = await HttpClient.instance.getText(
          "https://www.huya.com/$roomId",
          header: {"user-agent": kUserAgent},
        );
        var m = RegExp(r'"lProfileRoom":(\d+)')
            .firstMatch(html);
        if (m != null) realRoomId = m.group(1)!;
      } catch (_) {}
    }

    var roomInfo = await _getRoomInfo(realRoomId);
    var root = roomInfo["roomInfo"] ?? roomInfo;
    var tLiveInfo = root["tLiveInfo"];
    var tProfileInfo = root["tProfileInfo"];
    if (tLiveInfo == null) {
      throw "虎牙直播间($realRoomId)解析失败";
    }

    var lines = <HuyaLineModel>[];
    var streamInfo =
        tLiveInfo["tLiveStreamInfo"]?["vStreamInfo"]?["value"] ??
            [];
    for (var item in streamInfo) {
      if ((item["sFlvUrl"]?.toString() ?? "").isNotEmpty) {
        lines.add(
          HuyaLineModel(
            line: item["sFlvUrl"].toString(),
            lineType: HuyaLineType.flv,
            flvAntiCode: item["sFlvAntiCode"].toString(),
            hlsAntiCode: item["sHlsAntiCode"].toString(),
            streamName: item["sStreamName"].toString(),
            cdnType: item["sCdnType"].toString(),
            presenterUid: roomInfo["topSid"] ?? 0,
          ),
        );
      }
    }

    return LiveRoomDetail(
      cover: tLiveInfo["sScreenshot"]?.toString() ?? "",
      online: tLiveInfo["lTotalCount"] ?? 0,
      roomId: tLiveInfo["lProfileRoom"]?.toString() ?? realRoomId,
      title: tLiveInfo["sIntroduction"] ??
          tLiveInfo["sRoomName"] ??
          "",
      userName: tProfileInfo?["sNick"] ?? "虎牙主播",
      userAvatar: tProfileInfo?["sAvatar180"] ?? "",
      introduction: tLiveInfo["sIntroduction"] ?? "",
      status: root["eLiveStatus"] == 2,
      data: HuyaUrlDataModel(
        url: "",
        lines: lines,
        bitRates: [],
        uid: getUid(),
      ),
      danmakuData: HuyaDanmakuArgs(
        ayyuid: tLiveInfo["lYyid"] ?? 0,
        topSid: roomInfo["topSid"] ?? 0,
        subSid: roomInfo["subSid"] ?? 0,
      ),
      url: "https://www.huya.com/$realRoomId",
    );
  }

  Future<Map> _getRoomInfo(String roomId) async {
    var html = await HttpClient.instance.getText(
      "https://m.huya.com/$roomId",
      header: {"user-agent": kUserAgent},
    );
    var m = RegExp(
            r"window\.HNF_GLOBAL_INIT.=.\{[\s\S]*?\}[\s\S]*?</script>")
        .firstMatch(html);
    if (m == null) return {};
    var jsonText = m
        .group(0)!
        .replaceAll(RegExp(r"window\.HNF_GLOBAL_INIT.=."), "")
        .replaceAll("</script>", "")
        .replaceAllMapped(
            RegExp(r'function.*?\(.*?\).\{[\s\S]*?\}'),
            (_) => '""');
    var obj = json.decode(jsonText);
    obj["topSid"] = int.tryParse(
        RegExp(r'lChannelId":(\d+)')
                .firstMatch(html)
                ?.group(1) ??
            "0");
    obj["subSid"] = int.tryParse(
        RegExp(r'lSubChannelId":(\d+)')
                .firstMatch(html)
                ?.group(1) ??
            "0");
    return obj;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) {
    var data = detail.data as HuyaUrlDataModel;
    data.bitRates = [
      HuyaBitRateModel(name: "原画", bitRate: 0),
      HuyaBitRateModel(name: "高清", bitRate: 2000),
    ];
    return Future.value(data.bitRates
        .map((e) => LivePlayQuality(
            quality: e.name,
            data: {"urls": data.lines, "bitRate": e.bitRate}))
        .toList());
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    var urls = <String>[];
    for (var line in quality.data["urls"]) {
      var anti = await getCndTokenInfoEx(line.streamName);
      anti = buildAntiCode(
          line.streamName, line.presenterUid, anti);
      var url =
          '${line.line}/${line.streamName}.flv?$anti&codec=264';
      if (quality.data["bitRate"] > 0) {
        url += "&ratio=${quality.data["bitRate"]}";
      }
      urls.add(url);
    }
    return LivePlayUrl(
        urls: urls, headers: {"user-agent": HYSDK_UA});
  }

  Future<String> getCndTokenInfoEx(String stream) async {
    var tid = HuyaUserId()..sHuYaUA = "pc_exe&7060000&official";
    var req = GetCdnTokenExReq()
      ..tId = tid
      ..sStreamName = stream;
    var resp = await tupClient.tupRequest(
        "getCdnTokenInfoEx", req, GetCdnTokenExResp());
    return resp.sFlvToken;
  }

  String buildAntiCode(
      String stream, int uid, String antiCode) {
    var q = Uri(query: antiCode).queryParametersAll;
    if (!q.containsKey("fm")) return antiCode;
    var ctype = q["ctype"]?.first ?? "huya_pc_exe";
    var t = int.tryParse(q["t"]?.first ?? "0");
    var seq = uid + DateTime.now().millisecondsSinceEpoch;
    var sh =
        md5.convert(utf8.encode('$seq|$ctype|$t')).toString();
    var fm = utf8.decode(
        base64.decode(Uri.decodeComponent(q["fm"]!.first)));
    var pre = fm.split('_').first;
    var ws = q["wsTime"]!.first;
    var sec = md5
        .convert(utf8.encode(
            '${pre}_${rotl64(uid)}_${stream}_${sh}_$ws'))
        .toString();
    return "wsSecret=$sec&wsTime=$ws&seqid=$seq&ctype=$ctype&ver=1&t=$t&u=${rotl64(uid)}&fs=${q['fs']?.first}";
  }

  int rotl64(int t) =>
      (t & ~0xFFFFFFFF) |
      ((((t & 0xFFFFFFFF) << 8) |
              ((t & 0xFFFFFFFF) >> 24)) &
          0xFFFFFFFF);

  String getUid() {
    var s =
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    var r = Random();
    return List.generate(36, (i) {
      if ([8, 13, 18, 23].contains(i)) return "-";
      if (i == 14) return "4";
      return s[r.nextInt(16)];
    }).join();
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await _getRoomInfo(roomId))["roomInfo"]
          ?["eLiveStatus"] ==
      2;

  @override
  Future<LiveCategoryResult> getRecommendRooms(
          {int page = 1}) async =>
      getCategoryRooms(
          LiveSubCategory(
              id: "0", name: "推荐", parentId: "0"),
          page: page);

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
          String keyword,
          {int page = 1}) async =>
      LiveSearchAnchorResult(hasMore: false, items: []);
}

class HuyaUrlDataModel {
  final String url;
  final String uid;
  List<HuyaLineModel> lines;
  List<HuyaBitRateModel> bitRates;
  HuyaUrlDataModel(
      {required this.bitRates,
      required this.lines,
      required this.url,
      required this.uid});
}

enum HuyaLineType { flv, hls }

class HuyaLineModel {
  final String line;
  final String cdnType;
  final String flvAntiCode;
  final String hlsAntiCode;
  final String streamName;
  final HuyaLineType lineType;
  final int presenterUid;
  HuyaLineModel(
      {required this.line,
      required this.lineType,
      required this.flvAntiCode,
      required this.hlsAntiCode,
      required this.streamName,
      required this.cdnType,
      required this.presenterUid});
}

class HuyaBitRateModel {
  final String name;
  final int bitRate;
  HuyaBitRateModel({required this.bitRate, required this.name});
}
