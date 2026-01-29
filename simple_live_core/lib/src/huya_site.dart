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

  static Map<String, String> requestHeaders = {
    'Origin': 'https://www.huya.com',
    'Referer': 'https://www.huya.com/',
    'User-Agent': HYSDK_UA,
  };

  final BaseTarsHttp tupClient =
      BaseTarsHttp("http://wup.huya.com", "liveui", headers: requestHeaders);

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
      var items = await getSubCategores(item.id);
      item.children.addAll(items);
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

      subs.add(LiveSubCategory(
        id: gid,
        name: item["gameFullName"].toString(),
        parentId: id,
        pic: "https://huyaimg.msstatic.com/cdnimage/game/$gid-MS.jpg",
      ));
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
        "tagAll": 0,
        "gameId": category.id,
        "page": page
      },
    );
    var result = json.decode(resultText);
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["datas"]) {
      items.add(LiveRoomItem(
        roomId: item["profileRoom"].toString(),
        title: item["introduction"]?.toString() ?? item["roomName"].toString(),
        cover: item["screenshot"].toString(),
        userName: item["nick"].toString(),
        online: int.tryParse(item["totalCount"].toString()) ?? 0,
      ));
    }
    var hasMore = result["data"]["page"] < result["data"]["totalPage"];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    var urlData = detail.data as HuyaUrlDataModel;
    return urlData.bitRates
        .map((item) => LivePlayQuality(
              quality: item.name,
              data: {"urls": urlData.lines, "bitRate": item.bitRate},
            ))
        .toList();
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    var ls = <String>[];
    for (var element in quality.data["urls"]) {
      var line = element as HuyaLineModel;
      var antiCode = await getCndTokenInfoEx(line.streamName);
      var finalAnti =
          buildAntiCode(line.streamName, line.presenterUid, antiCode);
      var url = '${line.line}/${line.streamName}.flv?$finalAnti&codec=264';
      if (quality.data["bitRate"] > 0) {
        url += "&ratio=${quality.data["bitRate"]}";
      }
      ls.add(url);
    }
    return LivePlayUrl(urls: ls, headers: {"user-agent": HYSDK_UA});
  }

  String buildAntiCode(String stream, int presenterUid, String antiCode) {
    var mapAnti = Uri(query: antiCode).queryParametersAll;
    if (!mapAnti.containsKey("fm")) return antiCode;

    var ctype = mapAnti["ctype"]?.first ?? "huya_pc_exe";
    var platformId = int.tryParse(mapAnti["t"]?.first ?? "0") ?? 0;
    bool isWap = platformId == 103;
    var clacStartTime = DateTime.now().millisecondsSinceEpoch;

    var seqId = presenterUid + clacStartTime;
    final secretHash =
        md5.convert(utf8.encode('$seqId|$ctype|$platformId')).toString();
    final convertUid = rotl64(presenterUid);
    final calcUid = isWap ? presenterUid : convertUid;

    final fm = Uri.decodeComponent(mapAnti['fm']!.first);
    final secretPrefix = utf8.decode(base64.decode(fm)).split('_').first;
    var wsTime = mapAnti['wsTime']!.first;

    final secretStr =
        '${secretPrefix}_${calcUid}_${stream}_${secretHash}_$wsTime';
    final wsSecret = md5.convert(utf8.encode(secretStr)).toString();

    final rnd = Random();
    final ct =
        ((int.parse(wsTime, radix: 16) + rnd.nextDouble()) * 1000).toInt();
    final uuid = (((ct % 1e10) + rnd.nextDouble()) * 1e3 % 0xffffffff)
        .toInt()
        .toString();

    final Map<String, dynamic> res = {
      'wsSecret': wsSecret,
      'wsTime': wsTime,
      'seqid': seqId,
      'ctype': ctype,
      'ver': '1',
      'fs': mapAnti['fs']!.first,
      'fm': Uri.encodeComponent(mapAnti['fm']!.first),
      't': platformId,
    };
    if (isWap) {
      res['uid'] = presenterUid;
      res['uuid'] = uuid;
    } else {
      res['u'] = convertUid;
    }
    return res.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<String> getCndTokenInfoEx(String stream) async {
    var tid = HuyaUserId()..sHuYaUA = "pc_exe&7060000&official";
    var tReq = GetCdnTokenExReq()
      ..tId = tid
      ..sStreamName = stream;
    var resp = await tupClient.tupRequest(
        "getCdnTokenInfoEx", tReq, GetCdnTokenExResp());
    return resp.sFlvToken;
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://www.huya.com/cache.php",
      queryParameters: {
        "m": "LiveList",
        "do": "getLiveListByPage",
        "tagAll": 0,
        "page": page
      },
    );
    var result = json.decode(resultText);
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["datas"]) {
      items.add(LiveRoomItem(
        roomId: item["profileRoom"].toString(),
        title: item["introduction"]?.toString() ?? item["roomName"].toString(),
        cover: item["screenshot"].toString(),
        userName: item["nick"].toString(),
        online: int.tryParse(item["totalCount"].toString()) ?? 0,
      ));
    }
    var hasMore = result["data"]["page"] < result["data"]["totalPage"];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    var tLiveInfo = roomInfo["roomInfo"]["tLiveInfo"];
    var tProfileInfo = roomInfo["roomInfo"]["tProfileInfo"];

    var huyaLines = <HuyaLineModel>[];
    var huyaBiterates = <HuyaBitRateModel>[];

    var streamData = tLiveInfo["tLiveStreamInfo"]["vStreamInfo"]["value"];
    for (var item in streamData) {
      if ((item["sFlvUrl"]?.toString() ?? "").isNotEmpty) {
        huyaLines.add(HuyaLineModel(
          line: item["sFlvUrl"].toString(),
          lineType: HuyaLineType.flv,
          flvAntiCode: item["sFlvAntiCode"].toString(),
          hlsAntiCode: item["sHlsAntiCode"].toString(),
          streamName: item["sStreamName"].toString(),
          cdnType: item["sCdnType"].toString(),
          presenterUid: roomInfo["topSid"] ?? 0,
        ));
      }
    }

    var biterates = tLiveInfo["tLiveStreamInfo"]["vBitRateInfo"]["value"];
    for (var item in biterates) {
      var name = item["sDisplayName"].toString();
      if (name.contains("HDR")) continue;
      huyaBiterates.add(HuyaBitRateModel(bitRate: item["iBitRate"], name: name));
    }

    return LiveRoomDetail(
      cover: tLiveInfo["sScreenshot"].toString(),
      online: tLiveInfo["lTotalCount"] ?? 0,
      roomId: tLiveInfo["lProfileRoom"].toString(),
      title: tLiveInfo["sIntroduction"]?.toString() ?? tLiveInfo["sRoomName"]?.toString() ?? "",
      userName: tProfileInfo["sNick"].toString(),
      userAvatar: tProfileInfo["sAvatar180"].toString(),
      introduction: tLiveInfo["sIntroduction"].toString(),
      notice: roomInfo["welcomeText"]?.toString() ?? "",
      status: roomInfo["roomInfo"]["eLiveStatus"] == 2,
      data: HuyaUrlDataModel(
        url: "",
        lines: huyaLines,
        bitRates: huyaBiterates,
        uid: getUid(t: 13, e: 10),
      ),
      danmakuData: HuyaDanmakuArgs(
        ayyuid: tLiveInfo["lYyid"] ?? 0,
        topSid: roomInfo["topSid"] ?? 0,
        subSid: roomInfo["subSid"] ?? 0,
      ),
      url: "https://www.huya.com/$roomId",
    );
  }

  Future<Map> _getRoomInfo(String roomId) async {
    var resultText = await HttpClient.instance.getText(
      "https://m.huya.com/$roomId",
      header: {"user-agent": kUserAgent},
    );

    var match = RegExp(
            r"window\.HNF_GLOBAL_INIT\s*=\s*(\{[\s\S]*?\})\s*</script>")
        .firstMatch(resultText);

    if (match == null) throw "解析错误：找不到 HNF_GLOBAL_INIT";

    String jsonText = match.group(1)!;
    jsonText = jsonText.replaceAllMapped(
        RegExp(r'function.*?\(.*?\).\{[\s\S]*?\}'), (match) => '""');

    var jsonObj = json.decode(jsonText);
    jsonObj["topSid"] = int.tryParse(RegExp(r'lChannelId":([0-9]+)')
            .firstMatch(resultText)
            ?.group(1) ??
        "0");
    jsonObj["subSid"] = int.tryParse(RegExp(r'lSubChannelId":([0-9]+)')
            .firstMatch(resultText)
            ?.group(1) ??
        "0");
    return jsonObj;
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
    for (var item in result["response"]["3"]["docs"]) {
      var rId = item["room_id"].toString();
      if (rId == "0") rId = item["uid"].toString();
      items.add(LiveRoomItem(
        roomId: rId,
        title: item["game_introduction"] ?? item["game_roomName"] ?? "",
        cover: item["game_screenshot"] ?? "",
        userName: item["game_nick"] ?? "",
        online: int.tryParse(item["game_total_count"].toString()) ?? 0,
      ));
    }
    var hasMore = result["response"]["3"]["numFound"] > (page * 20);
    return LiveCategoryResult(hasMore: hasMore, items: items)
        as LiveSearchRoomResult;
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://search.cdn.huya.com/",
      queryParameters: {
        "m": "Search",
        "do": "getSearchContent",
        "q": keyword,
        "v": 1,
        "typ": -5,
        "rows": 20,
        "start": (page - 1) * 20,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveAnchorItem>[];
    for (var item in result["response"]["1"]["docs"]) {
      items.add(LiveAnchorItem(
        roomId: item["room_id"].toString(),
        avatar: item["game_avatarUrl180"].toString(),
        userName: item["game_nick"].toString(),
        liveStatus: item["gameLiveOn"],
      ));
    }
    var hasMore = result["response"]["1"]["numFound"] > (page * 20);
    return LiveSearchAnchorResult(hasMore: hasMore, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    try {
      var roomInfo = await _getRoomInfo(roomId);
      return roomInfo["roomInfo"]["eLiveStatus"] == 2;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) {
    return Future.value([]);
  }

  int rotl64(int t) {
    final low = t & 0xFFFFFFFF;
    final rotatedLow = ((low << 8) | (low >> 24)) & 0xFFFFFFFF;
    final high = t & ~0xFFFFFFFF;
    return high | rotatedLow;
  }

  String getUid({int? t, int? e}) {
    var n = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        .split("");
    var o = List.filled(36, '');
    if (t != null) {
      for (var i = 0; i < t; i++) o[i] = n[Random().nextInt(e ?? n.length)];
    } else {
      o[8] = o[13] = o[18] = o[23] = "-";
      o[14] = "4";
      for (var i = 0; i < 36; i++) {
        if (o[i].isEmpty) {
          var r = Random().nextInt(16);
          o[i] = n[19 == i ? 3 & r | 8 : r];
        }
      }
    }
    return o.join("");
  }
}

class HuyaUrlDataModel {
  final String url, uid;
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
  final String line, cdnType, flvAntiCode, hlsAntiCode, streamName;
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
