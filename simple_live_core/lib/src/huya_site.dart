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
  final String kUserAgent = "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0";
  static const String HYSDK_UA = "HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)";

  final BaseTarsHttp tupClient = BaseTarsHttp("http://wup.huya.com", "liveui", headers: {
    'Origin': baseUrl, 'Referer': baseUrl, 'User-Agent': HYSDK_UA,
  });

  @override String id = "huya";
  @override String name = "虎牙直播";
  @override LiveDanmaku getDanmaku() => HuyaDanmaku();

  // ---------------- 获取分类 ----------------
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
    var result = await HttpClient.instance.getJson("https://live.cdn.huya.com/liveconfig/game/bussLive", queryParameters: {"bussType": id});
    List<LiveSubCategory> subs = [];
    for (var item in result["data"]) {
      var gid = item["gid"] is Map ? item["gid"]["value"].toString().split(",").first : item["gid"].toString();
      subs.add(LiveSubCategory(id: gid, name: item["gameFullName"].toString(), parentId: id, pic: "https://huyaimg.msstatic.com/cdnimage/game/$gid-MS.jpg"));
    }
    return subs;
  }

  // ---------------- 详情解析 (包含 ID 换算) ----------------
  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    String realId = roomId;
    if (roomId.length >= 10) {
      try {
        var res = await HttpClient.instance.getText("https://www.huya.com/$roomId", header: {"user-agent": kUserAgent});
        var m = RegExp(r'\"lProfileRoom\":(\d+)').firstMatch(res);
        if (m != null) realId = m.group(1)!;
      } catch (_) {}
    }
    var roomInfo = await _getRoomInfo(realId);
    var rootData = roomInfo["roomInfo"] ?? roomInfo["data"] ?? roomInfo;
    var tLiveInfo = rootData["tLiveInfo"];
    if (tLiveInfo == null) tLiveInfo = roomInfo["data"]?["tLiveInfo"];
    if (tLiveInfo == null) throw "解析失败，主播可能已下播";

    var huyaLines = <HuyaLineModel>[];
    var streamInfo = tLiveInfo["tLiveStreamInfo"]?["vStreamInfo"]?["value"] ?? [];
    for (var item in streamInfo) {
      if ((item["sFlvUrl"]?.toString() ?? "").isNotEmpty) {
        huyaLines.add(HuyaLineModel(line: item["sFlvUrl"].toString(), lineType: HuyaLineType.flv, flvAntiCode: item["sFlvAntiCode"].toString(), hlsAntiCode: item["sHlsAntiCode"].toString(), streamName: item["sStreamName"].toString(), cdnType: item["sCdnType"].toString(), presenterUid: roomInfo["topSid"] ?? 0));
      }
    }
    return LiveRoomDetail(
      cover: tLiveInfo["sScreenshot"]?.toString() ?? "",
      online: tLiveInfo["lTotalCount"] ?? 0,
      roomId: tLiveInfo["lProfileRoom"]?.toString() ?? realId,
      title: tLiveInfo["sIntroduction"]?.toString() ?? tLiveInfo["sRoomName"]?.toString() ?? "",
      userName: rootData["tProfileInfo"]?["sNick"]?.toString() ?? "虎牙主播",
      userAvatar: rootData["tProfileInfo"]?["sAvatar180"]?.toString() ?? "",
      introduction: tLiveInfo["sIntroduction"]?.toString() ?? "",
      status: rootData["eLiveStatus"] == 2,
      data: HuyaUrlDataModel(url: "", lines: huyaLines, bitRates: [], uid: getUid()),
      danmakuData: HuyaDanmakuArgs(ayyuid: tLiveInfo["lYyid"] ?? 0, topSid: roomInfo["topSid"] ?? 0, subSid: roomInfo["subSid"] ?? 0),
      url: "https://www.huya.com/$realId",
    );
  }

  // ---------------- 核心修复：搜索逻辑 ----------------
  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async {
    var resText = await HttpClient.instance.getJson("https://search.cdn.huya.com/", queryParameters: {"m": "Search", "do": "getSearchContent", "q": keyword, "v": 4, "typ": -5, "rows": 20, "start": (page - 1) * 20});
    var result = json.decode(resText);
    var items = <LiveRoomItem>[];
    var resp = result?["response"] ?? {};
    
    List docs1 = resp["1"]?["docs"] ?? [];
    List docs3 = resp["3"]?["docs"] ?? [];

    for (var item in docs3) {
      try {
        // 1. 获取 ID：优先从 docs3 取 room_id，如果为 0，去 docs1 匹配主播名找 ID
        var rId = item["room_id"]?.toString() ?? "0";
        if (rId == "0" || rId == "null") {
          var match = docs1.firstWhere((e) => e["game_nick"] == item["game_nick"], orElse: () => null);
          rId = (match?["room_id"] ?? item["game_subChannel"] ?? "0").toString();
        }
        if (rId == "0") continue;

        // 2. 获取封面：从 docs3 拿 game_screenshot 并应用原作者的 OSS 处理
        var cover = (item["game_screenshot"] ?? item["game_imgUrl"] ?? "").toString();
        if (cover.isNotEmpty) {
          if (cover.startsWith("//")) cover = "https:$cover";
          if (!cover.contains("?")) cover += "?x-oss-process=style/w338_h190&";
        }

        items.add(LiveRoomItem(
          roomId: rId,
          title: item["game_introduction"]?.toString() ?? item["game_roomName"]?.toString() ?? "",
          cover: cover,
          userName: item["game_nick"]?.toString() ?? "",
          online: int.tryParse(item["game_total_count"]?.toString() ?? "0") ?? 0,
        ));
      } catch (_) { continue; }
    }
    return LiveSearchRoomResult(hasMore: (resp["3"]?["numFound"] ?? 0) > (page * 20), items: items);
  }

  // ---------------- 辅助加密方法 ----------------
  Future<Map> _getRoomInfo(String roomId) async {
    var resText = await HttpClient.instance.getText("https://m.huya.com/$roomId", header: {"user-agent": kUserAgent});
    var text = RegExp(r"window\.HNF_GLOBAL_INIT.=.\{[\s\S]*?\}[\s\S]*?</script>").firstMatch(resText)?.group(0);
    if (text == null) return {};
    var jsonText = text.replaceAll(RegExp(r"window\.HNF_GLOBAL_INIT.=."), '').replaceAll("</script>", "").replaceAllMapped(RegExp(r'function.*?\(.*?\).\{[\s\S]*?\}'), (match) => '""');
    var jsonObj = json.decode(jsonText);
    jsonObj["topSid"] = int.tryParse(RegExp(r'lChannelId":([0-9]+)').firstMatch(resText)?.group(1) ?? "0");
    jsonObj["subSid"] = int.tryParse(RegExp(r'lSubChannelId":([0-9]+)').firstMatch(resText)?.group(1) ?? "0");
    return jsonObj;
  }

  String buildAntiCode(String stream, int presenterUid, String antiCode) {
    var mapAnti = Uri(query: antiCode).queryParametersAll;
    if (!mapAnti.containsKey("fm")) return antiCode;
    var ctype = mapAnti["ctype"]?.first ?? "huya_pc_exe";
    var platId = int.tryParse(mapAnti["t"]?.first ?? "0");
    var seqId = presenterUid + DateTime.now().millisecondsSinceEpoch;
    var secretHash = md5.convert(utf8.encode('$seqId|$ctype|$platId')).toString();
    var fm = Uri.decodeComponent(mapAnti['fm']!.first);
    var secretPrefix = utf8.decode(base64.decode(fm)).split('_').first;
    var wsTime = mapAnti['wsTime']!.first;
    var wsSecret = md5.convert(utf8.encode('${secretPrefix}_${rotl64(presenterUid)}_${stream}_${secretHash}_$wsTime')).toString();
    return "wsSecret=$wsSecret&wsTime=$wsTime&seqid=$seqId&ctype=$ctype&ver=1&t=$platId&u=${rotl64(presenterUid)}&fs=${mapAnti['fs']?.first}";
  }

  Future<String> getCndTokenInfoEx(String stream) async {
    var tid = HuyaUserId()..sHuYaUA = "pc_exe&7060000&official";
    var tReq = GetCdnTokenExReq()..tId = tid..sStreamName = stream;
    var resp = await tupClient.tupRequest("getCdnTokenInfoEx", tReq, GetCdnTokenExResp());
    return resp.sFlvToken;
  }

  int rotl64(int t) => (t & ~0xFFFFFFFF) | ((((t & 0xFFFFFFFF) << 8) | ((t & 0xFFFFFFFF) >> 24)) & 0xFFFFFFFF);
  String getUid() {
    var n = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".split("");
    var o = List.filled(36, '');
    for (var i = 0; i < 36; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) o[i] = "-";
      else if (i == 14) o[i] = "4";
      else o[i] = n[Random().nextInt(16)];
    }
    return o.join("");
  }

  @override Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async => getCategoryRooms(LiveSubCategory(id: "0", name: "推荐", parentId: "0"), page: page);
  @override Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async => LiveSearchAnchorResult(hasMore: false, items: []);
  @override Future<bool> getLiveStatus({required String roomId}) async => (await _getRoomInfo(roomId))["roomInfo"]?["eLiveStatus"] == 2;
  @override Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) => Future.value([]);
  @override Future<List<LivePlayQuality>> getPlayQualites({required LiveRoomDetail detail}) {
    var urlData = detail.data as HuyaUrlDataModel;
    if (urlData.bitRates.isEmpty) urlData.bitRates = [HuyaBitRateModel(name: "原画", bitRate: 0), HuyaBitRateModel(name: "高清", bitRate: 2000)];
    return Future.value(urlData.bitRates.map((e) => LivePlayQuality(data: {"urls": urlData.lines, "bitRate": e.bitRate}, quality: e.name)).toList());
  }
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
class HuyaBitRateModel { final String name; final int bitRate; HuyaBitRateModel({required this.bitRate, required this.name}); }
