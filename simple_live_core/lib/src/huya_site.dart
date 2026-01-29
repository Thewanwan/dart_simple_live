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

  final BaseTarsHttp tupClient =
      BaseTarsHttp("http://wup.huya.com", "liveui", headers: {
    'Origin': baseUrl,
    'Referer': baseUrl,
    'User-Agent': HYSDK_UA,
  });

  @override
  String id = "huya";

  @override
  String name = "虎牙直播";

  @override
  LiveDanmaku getDanmaku() => HuyaDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    return [
      LiveCategory(id: "1", name: "网游", children: []),
      LiveCategory(id: "2", name: "单机", children: []),
      LiveCategory(id: "3", name: "手游", children: []),
      LiveCategory(id: "8", name: "娱乐", children: []),
    ];
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
      LiveSubCategory category,
      {int page = 1}) async {
    var text = await HttpClient.instance.getJson(
      "https://www.huya.com/cache.php",
      queryParameters: {
        "m": "LiveList",
        "do": "getLiveListByPage",
        "gameId": category.id,
        "page": page
      },
    );
    var jsonObj = json.decode(text);
    var items = <LiveRoomItem>[];

    for (var item in jsonObj["data"]["datas"]) {
      var cover = item["screenshot"].toString();
      if (cover.startsWith("//")) cover = "https:$cover";
      items.add(LiveRoomItem(
        roomId: item["profileRoom"].toString(),
        title: item["roomName"] ?? "",
        cover: cover,
        userName: item["nick"].toString(),
        online: int.tryParse(item["totalCount"].toString()) ?? 0,
      ));
    }

    return LiveCategoryResult(
      hasMore: jsonObj["data"]["page"] < jsonObj["data"]["totalPage"],
      items: items,
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    var data = detail.data as HuyaUrlDataModel;
    if (data.bitRates.isEmpty) {
      data.bitRates = [
        HuyaBitRateModel(name: "原画", bitRate: 0),
      ];
    }
    return data.bitRates
        .map((e) => LivePlayQuality(
              quality: e.name,
              data: {"urls": data.lines, "bitRate": e.bitRate},
            ))
        .toList();
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    var urls = <String>[];
    for (var line in quality.data["urls"]) {
      var anti = await getCndTokenInfoEx(line.streamName);
      anti = buildAntiCode(line.streamName, line.presenterUid, anti);
      var url = "${line.line}/${line.streamName}.flv?$anti";
      urls.add(url);
    }
    return LivePlayUrl(urls: urls, headers: {"user-agent": HYSDK_UA});
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    var root = roomInfo["roomInfo"] ?? roomInfo["data"] ?? roomInfo;
    var tLiveInfo = root["tLiveInfo"];
    var tProfileInfo = root["tProfileInfo"];
    if (tLiveInfo == null) throw "虎牙直播间解析失败";

    String cover =
        tLiveInfo["sRoomPic"]?.toString() ??
        tLiveInfo["sScreenshot"]?.toString() ??
        "";
    if (cover.startsWith("//")) cover = "https:$cover";

    var lines = <HuyaLineModel>[];
    var streams =
        tLiveInfo["tLiveStreamInfo"]?["vStreamInfo"]?["value"] ?? [];

    for (var item in streams) {
      lines.add(HuyaLineModel(
        line: item["sFlvUrl"],
        streamName: item["sStreamName"],
        flvAntiCode: item["sFlvAntiCode"],
        hlsAntiCode: item["sHlsAntiCode"],
        cdnType: item["sCdnType"],
        lineType: HuyaLineType.flv,
        presenterUid: roomInfo["topSid"] ?? 0,
      ));
    }

    return LiveRoomDetail(
      roomId: tLiveInfo["lProfileRoom"].toString(),
      title: tLiveInfo["sRoomName"] ?? "",
      cover: cover,
      userName: tProfileInfo?["sNick"] ?? "",
      online: tLiveInfo["lTotalCount"] ?? 0,
      status: root["eLiveStatus"] == 2,
      data: HuyaUrlDataModel(
        url: "",
        uid: getUid(),
        lines: lines,
        bitRates: [],
      ),
      danmakuData: HuyaDanmakuArgs(
        ayyuid: tLiveInfo["lYyid"] ?? 0,
        topSid: roomInfo["topSid"] ?? 0,
        subSid: roomInfo["subSid"] ?? 0,
      ),
      url: "https://www.huya.com/$roomId",
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    return LiveSearchRoomResult(hasMore: false, items: []);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    return LiveSearchAnchorResult(hasMore: false, items: []);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    return getCategoryRooms(
        LiveSubCategory(id: "0", name: "推荐", parentId: "0"),
        page: page);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    return (await _getRoomInfo(roomId))["roomInfo"]?["eLiveStatus"] == 2;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) async {
    return [];
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
        .replaceAll(RegExp(r"window\.HNF_GLOBAL_INIT.=."), '')
        .replaceAll("</script>", "");
    var obj = json.decode(jsonText);
    obj["topSid"] =
        int.tryParse(RegExp(r'lChannelId":(\d+)').firstMatch(html)?.group(1) ?? "0");
    obj["subSid"] =
        int.tryParse(RegExp(r'lSubChannelId":(\d+)').firstMatch(html)?.group(1) ?? "0");
    return obj;
  }

  String buildAntiCode(String stream, int uid, String antiCode) {
    return antiCode;
  }

  Future<String> getCndTokenInfoEx(String stream) async {
    var tid = HuyaUserId()..sHuYaUA = "pc_exe&7060000&official";
    var req = GetCdnTokenExReq()..tId = tid..sStreamName = stream;
    var resp =
        await tupClient.tupRequest("getCdnTokenInfoEx", req, GetCdnTokenExResp());
    return resp.sFlvToken;
  }

  String getUid() {
    var n = "0123456789abcdef".split("");
    return List.generate(32, (_) => n[Random().nextInt(16)]).join();
  }
}

class HuyaUrlDataModel {
  final String url;
  final String uid;
  List<HuyaLineModel> lines;
  List<HuyaBitRateModel> bitRates;
  HuyaUrlDataModel(
      {required this.url,
      required this.uid,
      required this.lines,
      required this.bitRates});
}

enum HuyaLineType { flv, hls }

class HuyaLineModel {
  final String line;
  final String streamName;
  final String flvAntiCode;
  final String hlsAntiCode;
  final String cdnType;
  final HuyaLineType lineType;
  final int presenterUid;
  HuyaLineModel(
      {required this.line,
      required this.streamName,
      required this.flvAntiCode,
      required this.hlsAntiCode,
      required this.cdnType,
      required this.lineType,
      required this.presenterUid});
}

class HuyaBitRateModel {
  final String name;
  final int bitRate;
  HuyaBitRateModel({required this.name, required this.bitRate});
}
