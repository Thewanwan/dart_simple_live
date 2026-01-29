import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:crypto/crypto.dart';
import 'package:simple_live_core/src/model/tars/get_cdn_token_ex_req.dart';
import 'package:simple_live_core/src/model/tars/get_cdn_token_ex_resp.dart';
import 'package:simple_live_core/src/model/tars/get_cdn_token_req.dart';
import 'package:simple_live_core/src/model/tars/get_cdn_token_resp.dart';
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

  String? playUserAgent;
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
      queryParameters: {
        "bussType": id,
      },
    );

    List<LiveSubCategory> subs = [];
    for (var item in result["data"]) {
      var gid = "";

      if (item["gid"] is Map) {
        gid = item["gid"]["value"].toString().split(",").first;
      } else if (item["gid"] is double) {
        gid = item["gid"].toInt().toString();
      } else if (item["gid"] is int) {
        gid = item["gid"].toString();
      } else {
        gid = item["gid"].toString();
      }

      var subCategory = LiveSubCategory(
        id: gid,
        name: item["gameFullName"].toString(),
        parentId: id,
        pic: "https://huyaimg.msstatic.com/cdnimage/game/$gid-MS.jpg",
      );
      subs.add(subCategory);
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
      var cover = item["screenshot"].toString();
      if (!cover.contains("?")) {
        cover += "?x-oss-process=style/w338_h190&";
      }
      var title = item["introduction"]?.toString() ?? "";
      if (title.isEmpty) {
        title = item["roomName"]?.toString() ?? "";
      }

      var roomItem = LiveRoomItem(
        roomId: item["profileRoom"].toString(),
        title: title,
        cover: cover,
        userName: item["nick"].toString(),
        online: int.tryParse(item["totalCount"].toString()) ?? 0,
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["page"] < result["data"]["totalPage"];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) {
    List<LivePlayQuality> qualities = <LivePlayQuality>[];
    var urlData = detail.data as HuyaUrlDataModel;
    if (urlData.bitRates.isEmpty) {
      urlData.bitRates = [
        HuyaBitRateModel(
          name: "原画",
          bitRate: 0,
        ),
        HuyaBitRateModel(name: "高清", bitRate: 2000),
      ];
    }

    for (var item in urlData.bitRates) {
      qualities.add(LivePlayQuality(
        data: {
          "urls": urlData.lines,
          "bitRate": item.bitRate,
        },
        quality: item.name,
      ));
    }

    return Future.value(qualities);
  }

  Future<String> getHuYaUA() async {
    if (playUserAgent != null) {
      return playUserAgent!;
    }
    try {
      var result = await HttpClient.instance.getJson(
        "https://github.iill.moe/xiaoyaocz/dart_simple_live/master/assets/play_config.json",
        queryParameters: {
          "ts": DateTime.now().millisecondsSinceEpoch,
        },
      );
      playUserAgent = json.decode(result)['huya']['user_agent'];
    } catch (e) {
      CoreLog.error(e);
    }
    return playUserAgent ?? HYSDK_UA;
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    var ls = <String>[];
    for (var element in quality.data["urls"]) {
      var line = element as HuyaLineModel;
      var url = await getPlayUrl(line, quality.data["bitRate"]);
      ls.add(url);
    }
    return LivePlayUrl(
      urls: ls,
      headers: {"user-agent": HYSDK_UA},
    );
  }

  Future<String> getPlayUrl(HuyaLineModel line, int bitRate) async {
    var antiCode = await getCndTokenInfoEx(line.streamName);
    antiCode = buildAntiCode(line.streamName, line.presenterUid, antiCode);
    var url = '${line.line}/${line.streamName}.flv?${antiCode}&codec=264';
    if (bitRate > 0) {
      url += "&ratio=$bitRate";
    }
    return url;
  }

  String buildAntiCode(String stream, int presenterUid, String antiCode) {
    var mapAnti = Uri(query: antiCode).queryParametersAll;
    if (!mapAnti.containsKey("fm")) {
      return antiCode;
    }

    var ctype = mapAnti["ctype"]?.first ?? "huya_pc_exe";
    var platformId = int.tryParse(mapAnti["t"]?.first ?? "0");

    bool isWap = platformId == 103;
    var clacStartTime = DateTime.now().millisecondsSinceEpoch;

    CoreLog.i(
        "using $presenterUid | ctype-{$ctype} | platformId - {$platformId} | isWap - {$isWap} | $clacStartTime");

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
    final Map<String, dynamic> antiCodeRes = {
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
      antiCodeRes.addAll({
        'uid': presenterUid,
        'uuid': uuid,
      });
    } else {
      antiCodeRes['u'] = convertUid;
    }

    return antiCodeRes.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<String> getCndTokenInfoEx(String stream) async {
    var func = "getCdnTokenInfoEx";
    var tid = HuyaUserId();
    tid.sHuYaUA = "pc_exe&7060000&official";
    var tReq = GetCdnTokenExReq();
    tReq.tId = tid;
    tReq.sStreamName = stream;
    var resp = await tupClient.tupRequest(func, tReq, GetCdnTokenExResp());
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
      var cover = item["screenshot"].toString();
      if (!cover.contains("?")) {
        cover += "?x-oss-process=style/w338_h190&";
      }
      var title = item["introduction"]?.toString() ?? "";
      if (title.isEmpty) {
        title = item["roomName"]?.toString() ?? "";
      }

      var roomItem = LiveRoomItem(
        roomId: item["profileRoom"].toString(),
        title: title,
        cover: cover,
        userName: item["nick"].toString(),
        online: int.tryParse(item["totalCount"].toString()) ?? 0,
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["page"] < result["data"]["totalPage"];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    
    // 兼容性修复：处理 roomInfo 结构可能缺失的情况
    var rootData = roomInfo["roomInfo"] ?? roomInfo;
    var tLiveInfo = rootData["tLiveInfo"];
    var tProfileInfo = rootData["tProfileInfo"];

    if (tLiveInfo == null || tProfileInfo == null) {
       throw "无法解析直播间信息，请尝试解析直链进入";
    }

    var title = tLiveInfo["sIntroduction"]?.toString() ?? "";
    if (title.isEmpty) {
      title = tLiveInfo["sRoomName"]?.toString() ?? "";
    }
    var huyaLines = <HuyaLineModel>[];
    var huyaBiterates = <HuyaBitRateModel>[];
    
    // 读取可用线路，增加判空
    var streamData = tLiveInfo["tLiveStreamInfo"]?["vStreamInfo"]?["value"];
    if (streamData != null) {
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
    }

    // 清晰度，增加判空
    var bitRateData = tLiveInfo["tLiveStreamInfo"]?["vBitRateInfo"]?["value"];
    if (bitRateData != null) {
      for (var item in bitRateData) {
        var name = item["sDisplayName"].toString();
        if (name.contains("HDR")) {
          continue;
        }
        huyaBiterates.add(HuyaBitRateModel(
          bitRate: item["iBitRate"] ?? 0,
          name: name,
        ));
      }
    }

    var topSid = roomInfo["topSid"];
    var subSid = roomInfo["subSid"];

    return LiveRoomDetail(
      cover: tLiveInfo["sScreenshot"]?.toString() ?? "",
      online: tLiveInfo["lTotalCount"] ?? 0,
      roomId: tLiveInfo["lProfileRoom"]?.toString() ?? roomId,
      title: title,
      userName: tProfileInfo["sNick"]?.toString() ?? "未知主播",
      userAvatar: tProfileInfo["sAvatar180"]?.toString() ?? "",
      introduction: tLiveInfo["sIntroduction"]?.toString() ?? "",
      notice: roomInfo["welcomeText"]?.toString() ?? "",
      status: rootData["eLiveStatus"] == 2,
      data: HuyaUrlDataModel(
        url: "https:${utf8.decode(base64.decode(roomInfo["roomProfile"]?["liveLineUrl"]?.toString() ?? ""))}",
        lines: huyaLines,
        bitRates: huyaBiterates,
        uid: getUid(t: 13, e: 10),
      ),
      danmakuData: HuyaDanmakuArgs(
        ayyuid: tLiveInfo["lYyid"] ?? 0,
        topSid: topSid ?? 0,
        subSid: subSid ?? 0,
      ),
      url: "https://www.huya.com/$roomId",
    );
  }

  Future<Map> _getRoomInfo(String roomId) async {
    var resultText = await HttpClient.instance.getText(
      "https://m.huya.com/$roomId",
      queryParameters: {},
      header: {
        "user-agent": kUserAgent,
      },
    );
    var text = RegExp(
            r"window\.HNF_GLOBAL_INIT.=.\{[\s\S]*?\}[\s\S]*?</script>",
            multiLine: false)
        .firstMatch(resultText)
        ?.group(0);
    var jsonText = text!
        .replaceAll(RegExp(r"window\.HNF_GLOBAL_INIT.=."), '')
        .replaceAll("</script>", "")
        .replaceAllMapped(RegExp(r'function.*?\(.*?\).\{[\s\S]*?\}'), (match) {
      return '""';
    });

    var jsonObj = json.decode(jsonText);
    var topSid = int.tryParse(
        RegExp(r'lChannelId":([0-9]+)').firstMatch(resultText)?.group(1) ??
            "0");
    var subSid = int.tryParse(
        RegExp(r'lSubChannelId":([0-9]+)').firstMatch(resultText)?.group(1) ??
            "0");
    jsonObj["topSid"] = topSid;
    jsonObj["subSid"] = subSid;
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
        "uid": 0,
        "v": 4,
        "typ": -5,
        "livestate": 0,
        "rows": 20,
        "start": (page - 1) * 20,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveRoomItem>[];
    
    // 根据真实数据结构 response -> 3 -> docs 进行解析
    var resp3 = result?["response"]?["3"];
    if (resp3 == null || resp3["docs"] == null) {
      return LiveSearchRoomResult(hasMore: false, items: []);
    }

    for (var item in resp3["docs"]) {
      try {
        // 关键：从扁平化的 item 中直接提取字段，避开不存在的 tLiveInfo
        var rawRoomId = item["game_subChannel"]?.toString() ?? "0";
        if (rawRoomId == "0" || rawRoomId == "") {
           rawRoomId = item["room_id"]?.toString() ?? "0";
        }
        
        var title = item["game_introduction"]?.toString() ?? item["game_roomName"]?.toString() ?? "";
        var cover = item["game_screenshot"]?.toString() ?? "";
        var nick = item["game_nick"]?.toString() ?? "";
        var online = int.tryParse(item["game_total_count"]?.toString() ?? "0") ?? 0;

        if (rawRoomId == "0") continue;

        items.add(LiveRoomItem(
          roomId: rawRoomId,
          title: title,
          cover: cover,
          userName: nick,
          online: online,
        ));
      } catch (e) {
        continue;
      }
    }
    var hasMore = (resp3["numFound"] ?? 0) > (page * 20);
    return LiveSearchRoomResult(hasMore: hasMore, items: items);
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
        "uid": 0,
        "v": 1,
        "typ": -5,
        "livestate": 0,
        "rows": 20,
        "start": (page - 1) * 20,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveAnchorItem>[];
    
    var resp1 = result?["response"]?["1"];
    if (resp1 == null || resp1["docs"] == null) {
       return LiveSearchAnchorResult(hasMore: false, items: []);
    }

    for (var item in resp1["docs"]) {
      try {
        var anchorItem = LiveAnchorItem(
          roomId: (item["game_subChannel"] ?? item["room_id"] ?? "0").toString(),
          avatar: item["game_avatarUrl180"]?.toString() ?? "",
          userName: item["game_nick"]?.toString() ?? "",
          liveStatus: item["gameLiveOn"] ?? false,
        );
        items.add(anchorItem);
      } catch (e) {
        continue;
      }
    }
    var hasMore = (resp1["numFound"] ?? 0) > (page * 20);
    return LiveSearchAnchorResult(hasMore: hasMore, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    var rootData = roomInfo["roomInfo"] ?? roomInfo;
    return rootData["eLiveStatus"] == 2;
  }

  Future<String> getAnonymousUid() async {
    var result = await HttpClient.instance.postJson(
      "https://udblgn.huya.com/web/anonymousLogin",
      data: {
        "appId": 5002,
        "byPass": 3,
        "context": "",
        "version": "2.4",
        "data": {}
      },
      header: {
        "user-agent": kUserAgent,
      },
    );
    return result["data"]["uid"].toString();
  }

  int rotl64(int t) {
    final low = t & 0xFFFFFFFF;
    final rotatedLow =
    ((low << 8) | (low >> 24)) & 0xFFFFFFFF;
    final high = t & ~0xFFFFFFFF;
    return high | rotatedLow;
  }

  String getUUid() {
    var currentTime = DateTime.now().millisecondsSinceEpoch;
    var randomValue = Random().nextInt(4294967295);
    var result = (currentTime % 10000000000 * 1000 + randomValue) % 4294967295;
    return result.toString();
  }

  String getUid({int? t, int? e}) {
    var n = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        .split("");
    var o = List.filled(36, '');
    if (t != null) {
      for (var i = 0; i < t; i++) {
        o[i] = n[Random().nextInt(e ?? n.length)];
      }
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

  String processAnticode(String anticode, String uid, String streamname) {
    var query = Uri.splitQueryString(anticode);

    query["t"] = "103";
    query["ctype"] = "tars_mobile";

    final wsTime = (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 21600)
        .toRadixString(16);
    final seqId =
        (DateTime.now().millisecondsSinceEpoch + int.parse(uid)).toString();

    final fm = utf8.decode(base64.decode(Uri.decodeComponent(query['fm']!)));
    final wsSecretPrefix = fm.split('_').first;
    final wsSecretHash = md5
        .convert(utf8.encode('$seqId|${query["ctype"]}|${query["t"]}'))
        .toString();
    final wsSecret = md5
        .convert(utf8.encode(
            '${wsSecretPrefix}_${uid}_${streamname}_${wsSecretHash}_$wsTime'))
        .toString();

    return Uri(queryParameters: {
      "wsSecret": wsSecret,
      "wsTime": wsTime,
      "seqid": seqId,
      "ctype": query["ctype"]!,
      "ver": "1",
      "fs": query["fs"]!,
      "dMod": "mseh-0",
      "sdkPcdn": "1_1",
      "uid": uid,
      "uuid": getUUid(),
      "t": query["t"]!,
      "sv": "202411221719",
      "sdk_sid": "1732862566708",
      "a_block": "0"
    }).query;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) {
    return Future.value([]);
  }
}

class HuyaUrlDataModel {
  final String url;
  final String uid;
  List<HuyaLineModel> lines;
  List<HuyaBitRateModel> bitRates;

  HuyaUrlDataModel({
    required this.bitRates,
    required this.lines,
    required this.url,
    required this.uid,
  });

  @override
  String toString() {
    return json.encode({
      "url": url,
      "uid": uid,
      "lines": lines.map((e) => e.toString()).toList(),
      "bitRates": bitRates.map((e) => e.toString()).toList(),
    });
  }
}

enum HuyaLineType {
  flv,
  hls,
}

class HuyaLineModel {
  final String line;
  final String cdnType;
  final String flvAntiCode;
  final String hlsAntiCode;
  final String streamName;
  final HuyaLineType lineType;
  int bitRate;
  final int presenterUid; 

  HuyaLineModel({
    required this.line,
    required this.lineType,
    required this.flvAntiCode,
    required this.hlsAntiCode,
    required this.streamName,
    required this.cdnType,
    this.bitRate = 0,
    required this.presenterUid,
  });

  @override
  String toString() {
    return json.encode({
      "line": line,
      "cdnType": cdnType,
      "flvAntiCode": flvAntiCode,
      "hlsAntiCode": hlsAntiCode,
      "streamName": streamName,
      "lineType": lineType.toString(),
      "presenterUid": presenterUid,
    });
  }
}

class HuyaBitRateModel {
  final String name;
  final int bitRate;

  HuyaBitRateModel({
    required this.bitRate,
    required this.name,
  });

  @override
  String toString() {
    return json.encode({
      "name": name,
      "bitRate": bitRate,
    });
  }
}
