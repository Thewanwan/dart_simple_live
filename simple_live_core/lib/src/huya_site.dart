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
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    String realRoomId = roomId;

    if (roomId.length >= 10) {
      try {
        var html = await HttpClient.instance.getText(
          "https://www.huya.com/$roomId",
          header: {"user-agent": kUserAgent},
        );
        var m = RegExp(r'"lProfileRoom":(\d+)').firstMatch(html);
        if (m != null) realRoomId = m.group(1)!;
      } catch (_) {}
    }

    var roomInfo = await _getRoomInfo(realRoomId);
    var root = roomInfo["roomInfo"] ?? roomInfo["data"] ?? roomInfo;

    var tLiveInfo = root["tLiveInfo"];
    var tProfileInfo = root["tProfileInfo"];
    if (tLiveInfo == null) throw "虎牙直播间($realRoomId)解析失败";

    String cover =
        tLiveInfo["sRoomPic"]?.toString() ??
        tLiveInfo["sScreenshot"]?.toString() ??
        "";

    if (cover.startsWith("//")) {
      cover = "https:$cover";
    }

    var lines = <HuyaLineModel>[];
    var streamInfo =
        tLiveInfo["tLiveStreamInfo"]?["vStreamInfo"]?["value"] ?? [];

    for (var item in streamInfo) {
      if ((item["sFlvUrl"] ?? "").toString().isNotEmpty) {
        lines.add(HuyaLineModel(
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

    var bitRates = <HuyaBitRateModel>[];
    var rateInfo =
        tLiveInfo["tLiveStreamInfo"]?["vBitRateInfo"]?["value"] ?? [];

    for (var item in rateInfo) {
      var name = item["sDisplayName"].toString();
      if (name.contains("HDR")) continue;
      bitRates.add(HuyaBitRateModel(
        bitRate: item["iBitRate"],
        name: name,
      ));
    }

    return LiveRoomDetail(
      cover: cover,
      online: tLiveInfo["lTotalCount"] ?? 0,
      roomId: tLiveInfo["lProfileRoom"]?.toString() ?? realRoomId,
      title:
          tLiveInfo["sIntroduction"]?.toString() ??
          tLiveInfo["sRoomName"]?.toString() ??
          "",
      userName: tProfileInfo?["sNick"]?.toString() ?? "虎牙主播",
      userAvatar: tProfileInfo?["sAvatar180"]?.toString() ?? "",
      introduction: tLiveInfo["sIntroduction"]?.toString() ?? "",
      status: root["eLiveStatus"] == 2,
      data: HuyaUrlDataModel(
        url: "",
        lines: lines,
        bitRates: bitRates,
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

    var script = RegExp(
      r"window\.HNF_GLOBAL_INIT.=.\{[\s\S]*?\}[\s\S]*?</script>",
    ).firstMatch(html)?.group(0);

    if (script == null) return {};

    var jsonText = script
        .replaceAll(RegExp(r"window\.HNF_GLOBAL_INIT.=."), '')
        .replaceAll("</script>", "")
        .replaceAllMapped(
          RegExp(r'function.*?\(.*?\).\{[\s\S]*?\}'),
          (_) => '""',
        );

    var obj = json.decode(jsonText);
    obj["topSid"] =
        int.tryParse(RegExp(r'lChannelId":(\d+)').firstMatch(html)?.group(1) ?? "0");
    obj["subSid"] =
        int.tryParse(RegExp(r'lSubChannelId":(\d+)').firstMatch(html)?.group(1) ?? "0");
    return obj;
  }

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

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await _getRoomInfo(roomId))["roomInfo"]?["eLiveStatus"] == 2;
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
  HuyaLineModel({
    required this.line,
    required this.lineType,
    required this.flvAntiCode,
    required this.hlsAntiCode,
    required this.streamName,
    required this.cdnType,
    required this.presenterUid,
  });
}

class HuyaBitRateModel {
  final String name;
  final int bitRate;
  HuyaBitRateModel({
    required this.bitRate,
    required this.name,
  });
}
