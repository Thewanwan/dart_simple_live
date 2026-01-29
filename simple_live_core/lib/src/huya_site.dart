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
      "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0";

  static const String HYSDK_UA =
      "HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)";

  static Map<String, String> requestHeaders = {
    'Origin': baseUrl,
    'Referer': baseUrl,
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
      var gid = item["gid"] is Map ? item["gid"]["value"].toString().split(",").first : item["gid"].toString();
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
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category, {int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://www.huya.com/cache.php",
      queryParameters: {"m": "LiveList", "do": "getLiveListByPage", "gameId": category.id, "page": page},
    );
    var result = json.decode(resultText);
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["datas"]) {
      items.add(LiveRoomItem(
        roomId: item["profileRoom"].toString(),
        title: item["introduction"] ?? item["roomName"] ?? "",
        cover: item["screenshot"].toString(),
        userName: item["nick"].toString(),
        online: int.tryParse(item["totalCount"].toString()) ?? 0,
      ));
    }
    return LiveCategoryResult(hasMore: result["data"]["page"] < result["data"]["totalPage"], items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoomDetail detail}) {
    var urlData = detail.data as HuyaUrlDataModel;
    if (urlData.bitRates.isEmpty) {
      urlData.bitRates = [HuyaBitRateModel(name: "原画", bitRate: 0), HuyaBitRateModel(name: "高清", bitRate: 2000)];
    }
    return Future.value(urlData.bitRates.map((e) => LivePlayQuality(data: {"urls": urlData.lines, "bitRate": e.bitRate}, quality: e.name)).toList());
  }

  @override
  Future<LivePlayUrl> getPlayUrls({required LiveRoomDetail detail, required LivePlayQuality quality}) async {
    var ls = <String>[];
    for (var line in quality.data["urls"] as List<HuyaLineModel>) {
      var antiCode = await getCndTokenInfoEx(line.streamName);
      antiCode = buildAntiCode(line.streamName, line.presenterUid, antiCode);
      var url = '${line.line}/${line.streamName}.flv?${antiCode}&codec=264';
      if (quality.data["bitRate"] > 0) url += "&ratio=${quality.data["bitRate"]}";
      ls.add(url);
    }
    return LivePlayUrl(urls: ls, headers: {"user-agent": HYSDK_UA});
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    
    // 多级路径解析方案，专门应对 Android 15 下的数据结构碎片化
    var rootData = roomInfo["roomInfo"] ?? roomInfo["data"] ?? roomInfo;
    var tLiveInfo = rootData["tLiveInfo"];
    var tProfileInfo = rootData["tProfileInfo"];

    if (tLiveInfo == null) {
       // 如果主路径失败，尝试在 data 节点深度搜索
       tLiveInfo = roomInfo["data"]?["tLiveInfo"];
       if (tLiveInfo == null) throw "虎牙直播间($roomId)解析失败：主播可能已下播或正在维护";
    }

    var huyaLines = <HuyaLineModel>[];
    var streamInfo = tLiveInfo["tLiveStreamInfo"]?["vStreamInfo"]?["value"] ?? [];
    for (var item in streamInfo) {
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

    return LiveRoomDetail(
      cover: tLiveInfo["sScreenshot"]?.toString() ?? "",
      online: tLiveInfo["lTotalCount"] ?? 0,
      roomId: tLiveInfo["lProfileRoom"]?.toString() ?? roomId,
      title: tLiveInfo["sIntroduction"]?.toString() ?? tLiveInfo["sRoomName"]?.toString() ?? "",
      userName: tProfileInfo?["sNick"]?.toString() ?? "虎牙主播",
      userAvatar: tProfileInfo?["sAvatar180"]?.toString() ?? "",
      introduction: tLiveInfo["sIntroduction"]?.toString() ?? "",
      status: rootData["eLiveStatus"] == 2,
      data: HuyaUrlDataModel(url: "", lines: huyaLines, bitRates: [], uid: getUid(t: 13, e: 10)),
      danmakuData: HuyaDanmakuArgs(ayyuid: tLiveInfo["lYyid"] ?? 0, topSid: roomInfo["topSid"] ?? 0, subSid: roomInfo["subSid"] ?? 0),
      url: "https://www.huya.com/$roomId",
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://search.cdn.huya.com/",
      queryParameters: {"m": "Search", "do": "getSearchContent", "q": keyword, "v": 4, "typ": -5, "rows": 20, "start": (page - 1) * 20},
    );
    var result = json.decode(resultText);
    var items = <LiveRoomItem>[];
    var docs = result?["response"]?["3"]?["docs"] ?? [];
    
    for (var item in docs) {
      // 核心修复：优先取短 ID (game_subChannel)，彻底避免长 ID (YYID) 的解析兼容性问题
      var rId = (item["game_subChannel"] ?? item["room_id"] ?? item["game_id"] ?? "0").toString();
      if (rId == "0") continue;

      items.add(LiveRoomItem(
        roomId: rId,
        title: item["game_introduction"]?.toString() ?? item["game_roomName"]?.toString() ?? "",
        cover: item["game_screenshot"]?.toString() ?? "",
        userName: item["game_nick"]?.toString() ?? "",
        online: int.tryParse(item["game_total_count"]?.toString() ?? "0") ?? 0,
      ));
    }
    return LiveSearchRoomResult(hasMore: (result?["response"]?["3"]?["numFound"] ?? 0) > (page * 20), items: items);
  }

  // --- 辅助方法与加密逻辑保持不变 ---
  Future<Map> _getRoomInfo(String roomId) async {
    var resultText = await HttpClient.instance.getText("https://m.huya.com/$roomId", header: {"user-agent": kUserAgent});
    var text = RegExp(r"window\.HNF_GLOBAL_INIT.=.\{[\s\S]*?\}[\s\S]*?</script>").firstMatch(resultText)?.group(0);
    if (text == null) return {};
    var jsonText = text.replaceAll(RegExp(r"window\.HNF_GLOBAL_INIT.=."), '').replaceAll("</script>", "")
        .replaceAllMapped(RegExp(r'function.*?\(.*?\).\{[\s\S]*?\}'), (match) => '""');
    var jsonObj = json.decode(jsonText);
    jsonObj["topSid"] = int.tryParse(RegExp(r'lChannelId":([0-9]+)').firstMatch(resultText)?.group(1) ?? "0");
    jsonObj["subSid"] = int.tryParse(RegExp(r'lSubChannelId":([0-9]+)').firstMatch(resultText)?.group(1) ?? "0");
    return jsonObj;
  }

  String buildAntiCode(String stream, int presenterUid, String antiCode) {
    var mapAnti = Uri(query: antiCode).queryParametersAll;
    if (!mapAnti.containsKey("fm")) return antiCode;
    var ctype = mapAnti["ctype"]?.first ?? "huya_pc_exe";
    var platformId = int.tryParse(mapAnti["t"]?.first ?? "0");
    var seqId = presenterUid + DateTime.now().millisecondsSinceEpoch;
    final secretHash = md5.convert(utf8.encode('$seqId|$ctype|$platformId')).toString();
    final fm = Uri.decodeComponent(mapAnti['fm']!.first);
    final secretPrefix = utf8.decode(base64.decode(fm)).split('_').first;
    var wsTime = mapAnti['wsTime']!.first;
    final wsSecret = md5.convert(utf8.encode('${secretPrefix}_${rotl64(presenterUid)}_${stream}_${secretHash}_$wsTime')).toString();
    return "wsSecret=$wsSecret&wsTime=$wsTime&seqid=$seqId&ctype=$ctype&ver=1&t=$platformId&u=${rotl64(presenterUid)}&fs=${mapAnti['fs']?.first}";
  }

  Future<String> getCndTokenInfoEx(String stream) async {
    var tid = HuyaUserId()..sHuYaUA = "pc_exe&7060000&official";
    var tReq = GetCdnTokenExReq()..tId = tid..sStreamName = stream;
    var resp = await tupClient.tupRequest("getCdnTokenInfoEx", tReq, GetCdnTokenExResp());
    return resp.sFlvToken;
  }

  int rotl64(int t) {
    final low = t & 0xFFFFFFFF;
    return (t & ~0xFFFFFFFF) | (((low << 8) | (low >> 24)) & 0xFFFFFFFF);
  }

  String getUid({int? t, int? e}) {
    var n = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".split("");
    var o = List.filled(36, '');
    for (var i = 0; i < 36; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) { o[i] = "-"; } 
      else if (i == 14) { o[i] = "4"; }
      else { o[i] = n[Random().nextInt(16)]; }
    }
    return o.join("");
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async => getCategoryRooms(LiveSubCategory(id: "0", name: "推荐", parentId: "0"), page: page);
  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async => LiveSearchAnchorResult(hasMore: false, items: []);
  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _getRoomInfo(roomId))["roomInfo"]?["eLiveStatus"] == 2;
  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) => Future.value([]);
}

class HuyaUrlDataModel {
  final String url; final String uid; List<HuyaLineModel> lines; List<HuyaBitRateModel> bitRates;
  HuyaUrlDataModel({required this.bitRates, required this.lines, required this.url, required this.uid});
}

enum HuyaLineType { flv, hls }

class HuyaLineModel {
  final String line; final String cdnType; final String flvAntiCode; final String hlsAntiCode; final String streamName; final HuyaLineType lineType; final int presenterUid;
  HuyaLineModel({required this.line, required this.lineType, required this.flvAntiCode, required this.hlsAntiCode, required this.streamName, required this.cdnType, required this.presenterUid});
}

class HuyaBitRateModel {
  final String name; final int bitRate;
  HuyaBitRateModel({required this.bitRate, required this.name});
}
