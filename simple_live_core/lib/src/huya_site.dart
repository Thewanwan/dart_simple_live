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
  /// 分类
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
      } else if (raw is int) {
        gid = raw.toString();
      } else if (raw is double) {
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
  /// 列表 / 推荐
  /// ---------------------------
  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) =>
      _fetchRoomList(
        extraQuery: {
          'gameId': category.id,
        },
        page: page,
      );

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) =>
      _fetchRoomList(page: page);

  Future<LiveCategoryResult> _fetchRoomList({
    required int page,
    Map<String, dynamic>? extraQuery,
  }) async {
    final params = <String, dynamic>{
      'm': 'LiveList',
      'do': 'getLiveListByPage',
      'tagAll': 0,
      'page': page,
      if (extraQuery != null) ...extraQuery,
    };

    final raw =
        await HttpClient.instance.getJson('https://www.huya.com/cache.php',
            queryParameters: params);
    final result = json.decode(raw);

    final datas = (result['data']?['datas'] ?? []) as List<dynamic>;
    final items = <LiveRoomItem>[];

    for (final item in datas) {
      final cover = normalizeCover(item['screenshot']?.toString() ?? '');
      final title =
          coalesceTitle(item['introduction'], item['roomName']) ?? '';
      items.add(
        LiveRoomItem(
          roomId: item['profileRoom'].toString(),
          title: title,
          cover: cover,
          userName: item['nick'].toString(),
          online: int.tryParse(item['totalCount'].toString()) ?? 0,
        ),
      );
    }

    final hasMore =
        (result['data']?['page'] ?? 0) < (result['data']?['totalPage'] ?? 0);
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  /// ---------------------------
  /// 播放线路 & 清晰度
  /// ---------------------------
  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) {
    final urlData = detail.data as HuyaUrlDataModel;

    if (urlData.bitRates.isEmpty) {
      urlData.bitRates = [
        HuyaBitRateModel(name: '原画', bitRate: 0),
        HuyaBitRateModel(name: '高清', bitRate: 2000),
      ];
    }

    final qualities = urlData.bitRates
        .map(
          (e) => LivePlayQuality(
            quality: e.name,
            data: {
              'urls': urlData.lines,
              'bitRate': e.bitRate,
            },
          ),
        )
        .toList();

    return Future.value(qualities);
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final urls = <String>[];
    final bitRate = quality.data['bitRate'] as int;
    final lines = quality.data['urls'] as List<HuyaLineModel>;

    for (final line in lines) {
      final url = await getPlayUrl(line, bitRate);
      urls.add(url);
    }

    final headers = {'user-agent': await _getPlaybackUserAgent()};
    return LivePlayUrl(urls: urls, headers: headers);
  }

  Future<String> getPlayUrl(HuyaLineModel line, int bitRate) async {
    var antiCode = await getCndTokenInfoEx(line.streamName);
    antiCode = buildAntiCode(line.streamName, line.presenterUid, antiCode);

    var url = '${line.line}/${line.streamName}.flv?$antiCode&codec=264';
    if (bitRate > 0) {
      url += '&ratio=$bitRate';
    }
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
    } catch (e) {
      CoreLog.error(e);
    }
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
        final convertRes = await HttpClient.instance.getText(
          'https://www.huya.com/$roomId',
          header: {'user-agent': kUserAgent},
        );
        final match = RegExp(r'"lProfileRoom":(\d+)').firstMatch(convertRes);
        if (match != null) realRoomId = match.group(1)!;
      } catch (_) {}
    }

    final roomInfo = await _getRoomInfo(realRoomId);
    final rootData = roomInfo['roomInfo'] ?? roomInfo['data'] ?? roomInfo;

    var tLiveInfo = rootData['tLiveInfo'];
    final tProfileInfo = rootData['tProfileInfo'];

    tLiveInfo ??= roomInfo['data']?['tLiveInfo'];
    if (tLiveInfo == null) {
      throw '虎牙直播间($realRoomId)解析失败';
    }

    final linesRaw =
        (tLiveInfo['tLiveStreamInfo']?['vStreamInfo']?['value'] ?? [])
            as List<dynamic>;
    final bitRatesRaw =
        (tLiveInfo['tLiveStreamInfo']?['vBitRateInfo']?['value'] ?? [])
            as List<dynamic>;

    final huyaLines = <HuyaLineModel>[];
    for (final item in linesRaw) {
      final flv = item['sFlvUrl']?.toString() ?? '';
      if (flv.isEmpty) continue;
      huyaLines.add(
        HuyaLineModel(
          line: flv,
          lineType: HuyaLineType.flv,
          flvAntiCode: item['sFlvAntiCode'].toString(),
          hlsAntiCode: item['sHlsAntiCode'].toString(),
          streamName: item['sStreamName'].toString(),
          cdnType: item['sCdnType'].toString(),
          presenterUid: roomInfo['topSid'] ?? 0,
        ),
      );
    }

    final huyaBitRates = <HuyaBitRateModel>[];
    for (final item in bitRatesRaw) {
      final name = item['sDisplayName']?.toString() ?? '';
      if (name.contains('HDR')) continue;
      huyaBitRates.add(
        HuyaBitRateModel(
          bitRate: item['iBitRate'] ?? 0,
          name: name.isEmpty ? '未知清晰度' : name,
        ),
      );
    }

    if (huyaBitRates.isEmpty) {
      huyaBitRates.addAll([
        HuyaBitRateModel(bitRate: 0, name: '原画'),
        HuyaBitRateModel(bitRate: 2000, name: '高清'),
      ]);
    }

    final title = coalesceTitle(
          tLiveInfo['sIntroduction'],
          tLiveInfo['sRoomName'],
        ) ??
        '';
    final cover = normalizeCover(tLiveInfo['sScreenshot']?.toString() ?? '');

    return LiveRoomDetail(
      cover: cover,
      online: tLiveInfo['lTotalCount'] ?? 0,
      roomId: tLiveInfo['lProfileRoom']?.toString() ?? realRoomId,
      title: title,
      userName: tProfileInfo?['sNick']?.toString() ?? '虎牙主播',
      userAvatar: tProfileInfo?['sAvatar180']?.toString() ?? '',
      introduction: tLiveInfo['sIntroduction']?.toString() ?? '',
      notice: roomInfo['welcomeText']?.toString() ?? '',
      status: (rootData['eLiveStatus'] ?? 0) == 2,
      data: HuyaUrlDataModel(
        url: tLiveInfo['sFlvUrl']?.toString() ?? '',
        lines: huyaLines,
        bitRates: huyaBitRates,
        uid: getUid(),
      ),
      // 注意：此处引用的 HuyaDanmakuArgs 必须在 core 库中已定义
      danmakuData: HuyaDanmakuArgs(
        ayyuid: tLiveInfo['lYyid'] ?? 0,
        topSid: roomInfo['topSid'] ?? 0,
        subSid: roomInfo['subSid'] ?? 0,
      ),
      url: 'https://www.huya.com/$realRoomId',
    );
  }

  Future<Map> _getRoomInfo(String roomId) async {
    final resultText = await HttpClient.instance.getText(
      'https://m.huya.com/$roomId',
      header: {'user-agent': kUserAgent},
    );

    final scriptMatch = RegExp(
      r'window\.HNF_GLOBAL_INIT.=.\{[\s\S]*?\}[\s\S]*?</script>',
    ).firstMatch(resultText)?.group(0);

    if (scriptMatch == null) return {};

    final jsonText = scriptMatch
        .replaceAll(RegExp(r'window\.HNF_GLOBAL_INIT.=.'), '')
        .replaceAll('</script>', '')
        .replaceAllMapped(
          RegExp(r'function.*?\(.*?\).\{[\s\S]*?\}'),
          (_) => '""',
        );

    final jsonObj = json.decode(jsonText);
    jsonObj['topSid'] =
        int.tryParse(RegExp(r'lChannelId":([0-9]+)').firstMatch(resultText)?.group(1) ?? '0');
    jsonObj['subSid'] =
        int.tryParse(RegExp(r'lSubChannelId":([0-9]+)').firstMatch(resultText)?.group(1) ?? '0');

    return jsonObj;
  }

  /// ---------------------------
  /// 搜索
  /// ---------------------------
  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    final raw = await HttpClient.instance.getJson(
      'https://search.cdn.huya.com/',
      queryParameters: {
        'm': 'Search',
        'do': 'getSearchContent',
        'q': keyword,
        'v': 4,
        'typ': -5,
        'rows': 20,
        'start': (page - 1) * 20,
      },
    );

    final result = json.decode(raw);
    final response = result['response'] ?? {};

    final docs = _pickSearchDocs(response);
    final items = <LiveRoomItem>[];

    for (final doc in docs) {
      try {
        final roomId = extractRoomId(doc);
        if (roomId == null) continue;

        final cover = normalizeCover(
          doc['game_screenshot']?.toString() ??
              doc['game_imgUrl']?.toString() ??
              doc['cover']?.toString() ??
              '',
        );

        final title = coalesceTitle(
              doc['game_introduction'],
              doc['live_intro'],
              doc['game_roomName'],
            ) ??
            '';

        items.add(
          LiveRoomItem(
            roomId: roomId,
            title: title,
            cover: cover,
            userName: doc['game_nick']?.toString() ?? '',
            online: int.tryParse(doc['game_total_count']?.toString() ??
                    doc['game_activityCount']?.toString() ??
                    '0') ??
                0,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    final numFound =
        (response['1']?['numFound']) ?? (response['3']?['numFound']) ?? 0;
    final hasMore = numFound > page * 20;

    return LiveSearchRoomResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    final raw = await HttpClient.instance.getJson(
      'https://search.cdn.huya.com/',
      queryParameters: {
        'm': 'Search',
        'do': 'getSearchContent',
        'q': keyword,
        'uid': 0,
        'v': 1,
        'typ': -5,
        'livestate': 0,
        'rows': 20,
        'start': (page - 1) * 20,
      },
    );

    final result = json.decode(raw);
    final docs =
        (result['response']?['1']?['docs'] ?? []) as List<dynamic>;

    final items = docs.map((doc) {
      final map = doc as Map<String, dynamic>;
      return LiveAnchorItem(
        roomId: map['room_id'].toString(),
        avatar: map['game_avatarUrl180']?.toString() ?? '',
        userName: map['game_nick']?.toString() ?? '',
        liveStatus: map['gameLiveOn'] ?? false,
      );
    }).toList();

    final numFound = result['response']?['1']?['numFound'] ?? 0;
    final hasMore = numFound > page * 20;

    return LiveSearchAnchorResult(hasMore: hasMore, items: items);
  }

  /// ---------------------------
  /// 其它
  /// ---------------------------
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final info = await _getRoomInfo(roomId);
    return info['roomInfo']?['eLiveStatus'] == 2;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
  }) =>
      Future.value([]);

  /// ---------------------------
  /// AntiCode & Token
  /// ---------------------------
  String buildAntiCode(String stream, int presenterUid, String antiCode) {
    final mapAnti = Uri(query: antiCode).queryParametersAll;
    if (!mapAnti.containsKey('fm')) return antiCode;

    final ctype = mapAnti['ctype']?.first ?? 'huya_pc_exe';
    final platformId = int.tryParse(mapAnti['t']?.first ?? '0') ?? 0;

    final seqId = presenterUid + DateTime.now().millisecondsSinceEpoch;
    final secretHash = md5.convert(utf8.encode('$seqId|$ctype|$platformId'));

    final convertUid = rotl64(presenterUid);

    final fm = Uri.decodeComponent(mapAnti['fm']!.first);
    final secretPrefix = utf8.decode(base64.decode(fm)).split('_').first;
    final wsTime = mapAnti['wsTime']!.first;
    final wsSecret = md5
        .convert(
          utf8.encode(
            '${secretPrefix}_${convertUid}_${stream}_${secretHash}_$wsTime',
          ),
        )
        .toString();

    final antiCodeRes = <String, String>{
      'wsSecret': wsSecret,
      'wsTime': wsTime,
      'seqid': seqId.toString(),
      'ctype': ctype,
      'ver': '1',
      'fs': mapAnti['fs']?.first ?? '',
      'fm': Uri.encodeComponent(mapAnti['fm']!.first),
      't': platformId.toString(),
      'u': convertUid.toString(),
    };

    return antiCodeRes.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<String> getCndTokenInfoEx(String stream) async {
    final req = GetCdnTokenExReq()
      ..tId = (HuyaUserId()..sHuYaUA = 'pc_exe&7060000&official')
      ..sStreamName = stream;

    final resp =
        await tupClient.tupRequest('getCdnTokenInfoEx', req, GetCdnTokenExResp());
    return resp.sFlvToken;
  }

  /// ---------------------------
  /// 工具函数
  /// ---------------------------
  static String normalizeCover(String raw) {
    if (raw.isEmpty) return raw;
    var cover = raw;
    if (cover.startsWith('//')) cover = 'https:$cover';
    if (!cover.contains('?')) {
      cover += '?x-oss-process=style/w338_h190&';
    }
    return cover;
  }

  static String? coalesceTitle(dynamic a, [dynamic b, dynamic c]) {
    final list = [a, b, c];
    for (final entry in list) {
      final str = entry?.toString() ?? '';
      if (str.trim().isNotEmpty) return str;
    }
    return null;
  }

  static List<Map<String, dynamic>> _pickSearchDocs(Map response) {
    final primary = response['1']?['docs'];
    if (primary is List && primary.isNotEmpty) {
      return primary.cast<Map<String, dynamic>>();
    }
    final secondary = response['3']?['docs'];
    if (secondary is List && secondary.isNotEmpty) {
      return secondary.cast<Map<String, dynamic>>();
    }
    return const [];
  }

  static String? extractRoomId(Map<String, dynamic> doc) {
    final roomId = doc['room_id'];
    if (roomId is int && roomId != 0) return roomId.toString();
    if (roomId is String && roomId.isNotEmpty && roomId != '0') return roomId;
    final fallback = doc['game_subChannel'] ?? doc['game_id'];
    if (fallback == null || fallback.toString() == '0') return null;
    return fallback.toString();
  }

  int rotl64(int t) => (t & ~0xFFFFFFFF) | ((((t & 0xFFFFFFFF) << 8) | ((t & 0xFFFFFFFF) >> 24)) & 0xFFFFFFFF);

  String getUid() {
    final chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.split('');
    final buffer = List.filled(36, '');

    buffer[8] = buffer[13] = buffer[18] = buffer[23] = '-';
    buffer[14] = '4';
    for (var i = 0; i < 36; i++) {
      if (buffer[i].isEmpty) {
        final r = Random().nextInt(16);
        buffer[i] = chars[i == 19 ? (r & 3) | 8 : r];
      }
    }
    return buffer.join('');
  }
}

/// ---------------------------
/// 数据模型 (仅保留此文件特有的模型)
/// ---------------------------

class HuyaUrlDataModel {
  HuyaUrlDataModel({
    required this.bitRates,
    required this.lines,
    required this.url,
    required this.uid,
  });

  final String url;
  final String uid;
  List<HuyaLineModel> lines;
  List<HuyaBitRateModel> bitRates;
}

enum HuyaLineType { flv, hls }

class HuyaLineModel {
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

  final String line;
  final HuyaLineType lineType;
  final String flvAntiCode;
  final String hlsAntiCode;
  final String streamName;
  final String cdnType;
  int bitRate;
  final int presenterUid;
}

class HuyaBitRateModel {
  HuyaBitRateModel({
    required this.bitRate,
    required this.name,
  });

  final String name;
  final int bitRate;
}
