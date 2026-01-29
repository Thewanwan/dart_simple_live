import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/model/tars/get_cdn_token_ex_req.dart';
import 'package:simple_live_core/src/model/tars/get_cdn_token_ex_resp.dart';
import 'package:simple_live_core/src/model/tars/huya_user_id.dart';
import 'package:tars_dart/tars/net/base_tars_http.dart';

class HuyaSite implements LiveSite {
  HuyaSite();

  static const String baseUrl = 'https://m.huya.com/';
  static const String kUserAgent =
      'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0';
  static const String HYSDK_UA =
      'HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)';

  static const Map<String, String> requestHeaders = {
    'Origin': baseUrl,
    'Referer': baseUrl,
    'User-Agent': HYSDK_UA,
  };

  final BaseTarsHttp tupClient =
      BaseTarsHttp('http://wup.huya.com', 'liveui', headers: requestHeaders);

  String? playUserAgent;

  @override
  String id = 'huya';

  @override
  String name = '虎牙直播';

  @override
  LiveDanmaku getDanmaku() => HuyaDanmaku();

  /// ---------------------------
  /// 分类获取
  /// ---------------------------
  @override
  Future<List<LiveCategory>> getCategores() async {
    final categories = <LiveCategory>[
      LiveCategory(id: '1', name: '网游', children: []),
      LiveCategory(id: '2', name: '单机', children: []),
      LiveCategory(id: '8', name: '娱乐', children: []),
      LiveCategory(id: '3', name: '手游', children: []),
    ];

    for (final category in categories) {
      final subs = await getSubCategores(category.id);
      category.children.addAll(subs);
    }
    return categories;
  }

  Future<List<LiveSubCategory>> getSubCategores(String id) async {
    final result = await HttpClient.instance.getJson(
      'https://live.cdn.huya.com/liveconfig/game/bussLive',
      queryParameters: {'bussType': id},
    );

    final data = (result?['data'] ?? []) as List<dynamic>;
    final subs = <LiveSubCategory>[];

    for (final item in data) {
      var gid = '';
      final dynamic raw = item['gid'];
      if (raw is Map) {
        gid = raw['value'].toString().split(',').first;
      } else if (raw is int || raw is double) {
        gid = raw.toInt().toString();
      } else if (raw != null) {
        gid = raw.toString();
      }

      subs.add(
        LiveSubCategory(
          id: gid,
          name: item['gameFullName'].toString(),
          parentId: id,
          pic: 'https://huyaimg.msstatic.com/cdnimage/game/$gid-MS.jpg',
        ),
      );
    }
    return subs;
  }

  /// ---------------------------
  /// 列表与推荐
  /// ---------------------------
  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category, {int page = 1}) =>
      _fetchRoomList(extraQuery: {'gameId': category.id}, page: page);

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) => _fetchRoomList(page: page);

  Future<LiveCategoryResult> _fetchRoomList({required int page, Map<String, dynamic>? extraQuery}) async {
    final params = <String, dynamic>{
      'm': 'LiveList',
      'do': 'getLiveListByPage',
      'tagAll': 0,
      'page': page,
      if (extraQuery != null) ...extraQuery,
    };

    final raw = await HttpClient.instance.getJson('https://www.huya.com/cache.php', queryParameters: params);
    final result = json.decode(raw);
    final datas = (result['data']?['datas'] ?? []) as List<dynamic>;
    final items = <LiveRoomItem>[];

    for (final item in datas) {
      items.add(LiveRoomItem(
        roomId: item['profileRoom'].toString(),
        title: coalesceTitle(item['introduction'], item['roomName']) ?? '',
        cover: normalizeCover(item['screenshot']?.toString() ?? ''),
        userName: item['nick'].toString(),
        online: int.tryParse(item['totalCount'].toString()) ?? 0,
      ));
    }

    final hasMore = (result['data']?['page'] ?? 0) < (result['data']?['totalPage'] ?? 0);
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  /// ---------------------------
  /// 播放逻辑
  /// ---------------------------
  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoomDetail detail}) {
    final urlData = detail.data as HuyaUrlDataModel;
    if (urlData.bitRates.isEmpty) {
      urlData.bitRates = [HuyaBitRateModel(name: '原画', bitRate: 0), HuyaBitRateModel(name: '高清', bitRate: 2000)];
    }
    return Future.value(urlData.bitRates.map((e) => LivePlayQuality(
      quality: e.name,
      data: {'urls': urlData.lines, 'bitRate': e.bitRate},
    )).toList());
  }

  @override
  Future<LivePlayUrl> getPlayUrls({required LiveRoomDetail detail, required LivePlayQuality quality}) async {
    final urls = <String>[];
    final bitRate = quality.data['bitRate'] as int;
    final lines = quality.data['urls'] as List<HuyaLineModel>;

    for (final line in lines) {
      urls.add(await getPlayUrl(line, bitRate));
    }
    return LivePlayUrl(urls: urls, headers: {'user-agent': await _getPlaybackUserAgent()});
  }

  Future<String> getPlayUrl(HuyaLineModel line, int bitRate) async {
    var antiCode = await getCndTokenInfoEx(line.streamName);
    antiCode = buildAntiCode(line.streamName, line.presenterUid, antiCode);
    var url = '${line.line}/${line.streamName}.flv?$antiCode&codec=264';
    if (bitRate > 0) url += '&ratio=$bitRate';
    return url;
  }

  Future<String> _getPlaybackUserAgent() async {
    if (playUserAgent != null) return playUserAgent!;
    try {
      final result = await HttpClient.instance.getJson(
        'https://github.iill.moe/xiaoyaocz/dart_simple_live/master/assets/play_config.json',
        queryParameters: {'ts': DateTime.now().millisecondsSinceEpoch},
      );
      playUserAgent = json.decode(result)['huya']['user_agent'];
    } catch (_) {}
    return playUserAgent ?? HYSDK_UA;
  }

  /// ---------------------------
  /// 房间详情
  /// ---------------------------
  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    var realRoomId = roomId;
    if (roomId.length >= 10) {
      try {
        final convertRes = await HttpClient.instance.getText('https://www.huya.com/$roomId', header: {'user-agent': kUserAgent});
        final match = RegExp(r'"lProfileRoom":(\d+)').firstMatch(convertRes);
        if (match != null) realRoomId = match.group(1)!;
      } catch (_) {}
    }

    final roomInfo = await _getRoomInfo(realRoomId);
    final rootData = roomInfo['roomInfo'] ?? roomInfo['data'] ?? roomInfo;
    var tLiveInfo = rootData['tLiveInfo'] ?? roomInfo['data']?['tLiveInfo'];
    
    if (tLiveInfo == null) throw '虎牙直播间($realRoomId)解析失败';

    final tProfileInfo = rootData['tProfileInfo'];
    final linesRaw = (tLiveInfo['tLiveStreamInfo']?['vStreamInfo']?['value'] ?? []) as List<dynamic>;
    final bitRatesRaw = (tLiveInfo['tLiveStreamInfo']?['vBitRateInfo']?['value'] ?? []) as List<dynamic>;

    final huyaLines = linesRaw.where((item) => item['sFlvUrl']?.toString().isNotEmpty ?? false).map((item) => HuyaLineModel(
      line: item['sFlvUrl'].toString(),
      lineType: HuyaLineType.flv,
      flvAntiCode: item['sFlvAntiCode'].toString(),
      hlsAntiCode: item['sHlsAntiCode'].toString(),
      streamName: item['sStreamName'].toString(),
      cdnType: item['sCdnType'].toString(),
      presenterUid: roomInfo['topSid'] ?? 0,
    )).toList();

    final huyaBitRates = bitRatesRaw.map((item) => HuyaBitRateModel(
      bitRate: item['iBitRate'] ?? 0,
      name: item['sDisplayName']?.toString() ?? '清晰度',
    )).where((e) => !e.name.contains('HDR')).toList();

    return LiveRoomDetail(
      cover: normalizeCover(tLiveInfo['sScreenshot']?.toString() ?? ''),
      online: tLiveInfo['lTotalCount'] ?? 0,
      roomId: tLiveInfo['lProfileRoom']?.toString() ?? realRoomId,
      title: coalesceTitle(tLiveInfo['sIntroduction'], tLiveInfo['sRoomName']) ?? '',
      userName: tProfileInfo?['sNick']?.toString() ?? '虎牙主播',
      userAvatar: tProfileInfo?['sAvatar180']?.toString() ?? '',
      introduction: tLiveInfo['sIntroduction']?.toString() ?? '',
      status: (rootData['eLiveStatus'] ?? 0) == 2,
      data: HuyaUrlDataModel(url: '', lines: huyaLines, bitRates: huyaBitRates, uid: getUid()),
      danmakuData: HuyaDanmakuArgs(ayyuid: tLiveInfo['lYyid'] ?? 0, topSid: roomInfo['topSid'] ?? 0, subSid: roomInfo['subSid'] ?? 0),
      url: 'https://www.huya.com/$realRoomId',
    );
  }

  Future<Map> _getRoomInfo(String roomId) async {
    final resultText = await HttpClient.instance.getText('https://m.huya.com/$roomId', header: {'user-agent': kUserAgent});
    final scriptMatch = RegExp(r'window\.HNF_GLOBAL_INIT.=.\{[\s\S]*?\}[\s\S]*?</script>').firstMatch(resultText)?.group(0);
    if (scriptMatch == null) return {};

    final jsonText = scriptMatch.replaceAll(RegExp(r'window\.HNF_GLOBAL_INIT.=.'), '').replaceAll('</script>', '').replaceAllMapped(RegExp(r'function.*?\(.*?\).\{[\s\S]*?\}'), (_) => '""');
    final jsonObj = json.decode(jsonText);
    jsonObj['topSid'] = int.tryParse(RegExp(r'lChannelId":([0-9]+)').firstMatch(resultText)?.group(1) ?? '0');
    jsonObj['subSid'] = int.tryParse(RegExp(r'lSubChannelId":([0-9]+)').firstMatch(resultText)?.group(1) ?? '0');
    return jsonObj;
  }

  /// ---------------------------
  /// 搜索逻辑
  /// ---------------------------
  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async {
    final raw = await HttpClient.instance.getJson('https://search.cdn.huya.com/', queryParameters: {
      'm': 'Search', 'do': 'getSearchContent', 'q': keyword, 'v': 4, 'typ': -5, 'rows': 20, 'start': (page - 1) * 20,
    });
    final response = json.decode(raw)['response'] ?? {};
    final docs = _pickSearchDocs(response);
    final items = docs.map((doc) {
      final rId = extractRoomId(doc);
      if (rId == null) return null;
      return LiveRoomItem(
        roomId: rId,
        title: coalesceTitle(doc['game_introduction'], doc['live_intro'], doc['game_roomName']) ?? '',
        cover: normalizeCover(doc['game_screenshot']?.toString() ?? doc['game_imgUrl']?.toString() ?? doc['cover']?.toString() ?? ''),
        userName: doc['game_nick']?.toString() ?? '',
        online: int.tryParse(doc['game_total_count']?.toString() ?? doc['game_activityCount']?.toString() ?? '0') ?? 0,
      );
    }).whereType<LiveRoomItem>().toList();

    return LiveSearchRoomResult(hasMore: ((response['1']?['numFound']) ?? 0) > page * 20, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async {
    final raw = await HttpClient.instance.getJson('https://search.cdn.huya.com/', queryParameters: {
      'm': 'Search', 'do': 'getSearchContent', 'q': keyword, 'v': 1, 'typ': -5, 'rows': 20, 'start': (page - 1) * 20,
    });
    final docs = (json.decode(raw)['response']?['1']?['docs'] ?? []) as List<dynamic>;
    return LiveSearchAnchorResult(hasMore: false, items: docs.map((doc) => LiveAnchorItem(
      roomId: doc['room_id'].toString(),
      avatar: doc['game_avatarUrl180']?.toString() ?? '',
      userName: doc['game_nick']?.toString() ?? '',
      liveStatus: doc['gameLiveOn'] ?? false,
    )).toList());
  }

  /// ---------------------------
  /// 加密与工具
  /// ---------------------------
  String buildAntiCode(String stream, int presenterUid, String antiCode) {
    final mapAnti = Uri(query: antiCode).queryParametersAll;
    if (!mapAnti.containsKey('fm')) return antiCode;
    final ctype = mapAnti['ctype']?.first ?? 'huya_pc_exe';
    final platformId = int.tryParse(mapAnti['t']?.first ?? '0') ?? 0;
    final seqId = presenterUid + DateTime.now().millisecondsSinceEpoch;
    final secretHash = md5.convert(utf8.encode('$seqId|$ctype|$platformId'));
    final fm = Uri.decodeComponent(mapAnti['fm']!.first);
    final secretPrefix = utf8.decode(base64.decode(fm)).split('_').first;
    final wsTime = mapAnti['wsTime']!.first;
    final wsSecret = md5.convert(utf8.encode('${secretPrefix}_${rotl64(presenterUid)}_${stream}_${secretHash}_$wsTime')).toString();
    return "wsSecret=$wsSecret&wsTime=$wsTime&seqid=$seqId&ctype=$ctype&ver=1&t=$platformId&u=${rotl64(presenterUid)}&fs=${mapAnti['fs']?.first}";
  }

  Future<String> getCndTokenInfoEx(String stream) async {
    final req = GetCdnTokenExReq()..tId = (HuyaUserId()..sHuYaUA = 'pc_exe&7060000&official')..sStreamName = stream;
    final resp = await tupClient.tupRequest('getCdnTokenInfoEx', req, GetCdnTokenExResp());
    return resp.sFlvToken;
  }

  static String normalizeCover(String raw) {
    if (raw.isEmpty) return '';
    var cover = raw.startsWith('//') ? 'https:$raw' : raw;
    return cover.contains('?') ? cover : '$cover?x-oss-process=style/w338_h190&';
  }

  static String? coalesceTitle(dynamic a, [dynamic b, dynamic c]) =>
      [a, b, c].firstWhere((e) => e?.toString().trim().isNotEmpty ?? false, orElse: () => null)?.toString();

  static List<Map<String, dynamic>> _pickSearchDocs(Map response) =>
      ((response['1']?['docs'] ?? response['3']?['docs'] ?? []) as List).cast<Map<String, dynamic>>();

  static String? extractRoomId(Map doc) {
    final rid = doc['room_id'];
    if (rid != null && rid != 0 && rid != '0') return rid.toString();
    final fallback = doc['game_subChannel'] ?? doc['game_id'];
    return (fallback != null && fallback != 0) ? fallback.toString() : null;
  }

  int rotl64(int t) => (t & ~0xFFFFFFFF) | ((((t & 0xFFFFFFFF) << 8) | ((t & 0xFFFFFFFF) >> 24)) & 0xFFFFFFFF);

  String getUid() {
    final chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.split('');
    final buffer = List.generate(36, (i) {
      if ([8, 13, 18, 23].contains(i)) return '-';
      if (i == 14) return '4';
      return chars[Random().nextInt(16)];
    });
    return buffer.join('');
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _getRoomInfo(roomId))['roomInfo']?['eLiveStatus'] == 2;
  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) => Future.value([]);
}

/// ---------------------------
/// 数据模型
/// ---------------------------
class HuyaDanmakuArgs {
  final int ayyuid, topSid, subSid;
  HuyaDanmakuArgs({required this.ayyuid, required this.topSid, required this.subSid});
}

class HuyaDanmaku extends LiveDanmaku {
  @override
  Future<bool> connect(dynamic danmakuData) async => true;
  @override
  void stop() {}
  @override
  Stream<LiveDanmakuItem> get danmakuStream => const Stream.empty();
}

class HuyaUrlDataModel {
  final String url, uid; List<HuyaLineModel> lines; List<HuyaBitRateModel> bitRates;
  HuyaUrlDataModel({required this.bitRates, required this.lines, required this.url, required this.uid});
}

enum HuyaLineType { flv, hls }

class HuyaLineModel {
  final String line, flvAntiCode, hlsAntiCode, streamName, cdnType; final HuyaLineType lineType; final int presenterUid;
  HuyaLineModel({required this.line, required this.lineType, required this.flvAntiCode, required this.hlsAntiCode, required this.streamName, required this.cdnType, required this.presenterUid});
}

class HuyaBitRateModel {
  final String name; final int bitRate;
  HuyaBitRateModel({required this.bitRate, required this.name});
}
