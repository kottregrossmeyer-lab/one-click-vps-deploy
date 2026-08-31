const DEFAULT_DASHBOARD = 'https://mirror.notebase.cn/download/yacd-ui.zip';
// GEOIP 兜底库(自托管于 mirror, 只是 IP→国家映射表, 相对稳定, 不需要天天更新)
const DEFAULT_RULE_SERVER = 'https://mirror.notebase.cn/rules';

// ═════════════════════════════════════════════════════════════
// 纯硬编码域名/IP 列表 —— 已按服务/厂商分类填充，可自行增删调整
// 结构沿用原设计：DIRECT_SUFFIX / DIRECT_DOMAIN / PROXY_SUFFIX /
// PROXY_DOMAIN / PROXY_OVERRIDE / PROXY_KEYWORD / PROXY_IP_CIDR
// 数组内用 # 注释块分组，块内按字母序
// ═════════════════════════════════════════════════════════════

// DIRECT_SUFFIX：域名后缀匹配（按服务/厂商分类，块内按字母序）
const DIRECT_SUFFIX = [
  // #Apple (12)
  'aaplimg.com', 'apple-cloudkit.com', 'apple-dns.net', 'apple.co', 'apple.com', 'apple.news',
  'appstore.com', 'cdn-apple.com', 'icloud-content.com', 'icloud.com', 'me.com', 'mzstatic.com',

  // #Microsoft (14)
  'microsoft.com', 'microsoftonline.com', 'msecnd.net', 'msftconnecttest.com', 'msftncsi.com',
  'office.com', 'office365.com', 'outlook.com', 's-microsoft.com', 'sharepoint.com',
  'visualstudio.com', 'windows.com', 'windowsupdate.com', 'xbox.com',

  // #腾讯系 (25)
  'dns.pub', 'dnspod.com', 'doh.pub', 'gcloudcs.com', 'gtimg.com', 'idqqimg.com', 'myapp.com',
  'myqcloud.com', 'qcloud.com', 'qidian.com', 'qq.com', 'servicewechat.com', 'tencent-cloud.com',
  'tencent-cloud.net', 'tencent.com', 'tencentcloud.com', 'tencentmusic.com', 'tenpay.com',
  'wechat.com', 'weishi.com', 'weixin.com', 'weixinbridge.com', 'weiyun.com', 'wxlivecdn.com',
  'wxwork.com',

  // #阿里系 (35)
  '1688.com', 'alibaba-inc.com', 'alibaba.com', 'alicdn.com', 'alidns.com', 'alikunlun.com',
  'alipan.com', 'alipay.com', 'aliyun.com', 'aliyuncs.com', 'aliyundrive.com', 'amap.com',
  'antfin.com', 'antgroup.com', 'autonavi.com', 'cainiao.com', 'dingtalk.com', 'ele.me',
  'elemecdn.com', 'etao.com', 'fliggy.com', 'freshippo.com', 'mxhichina.com', 'taobao.com',
  'taopiaopiao.com', 'teambition.com', 'tmall.com', 'tmall.hk', 'wandoujia.com', 'xiami.com',
  'xiami.net', 'ykimg.com', 'youku.com', 'yunos.com', 'yuque.com',

  // #字节系 (50)
  'animebytes.tv', 'byte008.com', 'bytedance.com', 'bytedns.net', 'byteimg.com', 'bytelb.net',
  'dongchedi.com', 'douyin.com', 'douyinact.com', 'douyinact.net', 'douyincdn.com',
  'douyinclips.com', 'douyincloud.net', 'douyincloud.run', 'douyinec.com', 'douyinhanyu.com',
  'douyinliving.com', 'douyinmusicclips.com', 'douyinmusicpromotion.com', 'douyinmusicvideo.com',
  'douyinpay.com', 'douyinpic.com', 'douyinshortvideo.com', 'douyinstatic.com', 'douyinvideo.net',
  'douyinvod.com', 'fanqienovel.com', 'feiliao.com', 'feishu.cn', 'feishu.com', 'huoshan.com',
  'huoshanlive.com', 'idouyinliving.com', 'idouyinpic.com', 'idouyinstatic.com', 'idouyinvod.com',
  'iesdouyin.com', 'iesdouyin.net', 'ihuoshanlive.com', 'ixigua.com', 'kaiyanapp.com',
  'larkoffice.com', 'larksuite.com', 'pstatp.com', 'snssdk.com', 'toutiao.com', 'toutiaoapi.com',
  'volcengine.com', 'volces.com', 'zijieapi.com',

  // #百度系 (11)
  'baidu.com', 'baidubcr.com', 'baidupcs.com', 'bcebos.com', 'bdatu.com', 'bdimg.com',
  'bdstatic.com', 'bdurl.net', 'duxiaoman.com', 'hao123.com', 'yunjiasu-cdn.net',

  // #京东系 (7)
  '360buy.com', '360buyimg.com', 'jcloud.com', 'jd.com', 'jd.hk', 'jdpay.com', 'jdwl.com',

  // #拼多多系 (3)
  'pddpic.com', 'pinduoduo.com', 'yangkeduo.com',

  // #美团系 (9)
  'dianping.com', 'maoyan.com', 'meituan.com', 'meituan.net', 'meitudata.com', 'meitustat.com',
  'meixincdn.com', 'mobike.com', 'sankuai.com',

  // #美图 (2)
  'meipai.com', 'meitu.com',

  // #小米系 (8)
  'mi-img.com', 'mi.com', 'mipay.com', 'miui.com', 'miwifi.com', 'redmi.com', 'xiaomi.com',
  'xiaomi.net',

  // #网易系 (11)
  '126.com', '126.net', '127.net', '163.com', '163yun.com', 'duokan.com', 'kaola.com',
  'lofter.com', 'netease.com', 'ydstatic.com', 'youdao.com',

  // #快手系 (5)
  'gifshow.com', 'kuaishou.com', 'kuaishou.tv', 'kwimgs.com', 'yximgs.com',

  // #哔哩哔哩 (7)
  'acgvideo.com', 'biliapi.com', 'biliapi.net', 'bilibili.com', 'bilibili.tv', 'bilivideo.com',
  'hdslb.com',

  // #爱奇艺 (3)
  'iqiyi.com', 'iqiyipic.com', 'qiyi.com',

  // #视频平台 (11)
  'aixifan.com', 'baofeng.com', 'fun.tv', 'hitv.com', 'le.com', 'letv.com', 'maoyun.tv',
  'mgtv.com', 'miaopai.com', 'pptv.com', 'v-56.com',

  // #直播 (6)
  'chushou.tv', 'douyu.com', 'huajiao.com', 'huanju.com', 'huya.com', 'yy.com',

  // #新闻媒体 (16)
  'cailianpress.com', 'cctv.com', 'cctvpic.com', 'china.com', 'chinanews.com', 'huanqiu.com',
  'huxiucdn.com', 'ifeng.com', 'jiemian.com', 'livechina.com', 'myzaker.com', 'qdaily.com',
  'takungpao.com', 'xinhuanet.com', 'yidianzixun.com', 'zhongguowangshi.com',

  // #科技媒体 (5)
  '36kr.com', 'cnbeta.com', 'huxiu.com', 'ifanr.com', 'pingwest.com',

  // #知乎 (2)
  'zhihu.com', 'zhimg.com',

  // #小红书 (2)
  'xhscdn.com', 'xiaohongshu.com',

  // #豆瓣 (2)
  'douban.com', 'doubanio.com',

  // #社交-国内 (5)
  'immomo.com', 'kaixin001.com', 'renren.com', 'tantanapp.com', 'xiaonei.com',

  // #新浪微博 (4)
  'sina.com', 'weibo.com', 'weibocdn.com', 'weico.cc',

  // #搜狐搜狗 (7)
  'sogo.com', 'sogou.com', 'sogoucdn.com', 'sohu-inc.com', 'sohu.com', 'sohucs.com', 'soku.com',

  // #360 (6)
  '360.com', '360in.com', 'qhimg.com', 'qhres.com', 'qihoo.com', 'so.com',

  // #滴滴系 (4)
  'didi.com', 'didialift.com', 'didiglobal.com', 'udache.com',

  // #携程/OTA (9)
  'ctrip.com', 'elong.com', 'ly.com', 'qunar.com', 'qyer.com', 'qyerstatic.com', 'tongcheng.com',
  'trip.com', 'tuniu.com',

  // #交通/出行 (9)
  '12306.com', 'ceair.com', 'csair.com', 'hellobike.com', 'hnair.com', 'ishansong.com',
  'qingju.com', 'umetrip.com', 'zuche.com',

  // #苏宁 (1)
  'suning.com',

  // #OPPO/一加/realme (4)
  'heytapmobi.com', 'oneplus.com', 'oppo.com', 'realme.com',

  // #华为荣耀 (5)
  'hicloud.com', 'honor.com', 'huawei.com', 'huaweicloud.com', 'vmall.com',

  // #联想 (2)
  'lenovo.com', 'thinkpad.com',

  // #手机/数码 (6)
  'coolpad.com', 'gfan.com', 'nubia.com', 'samsung.com', 'smartisan.com', 'vivo.com',

  // #魅族 (1)
  'meizu.com',

  // #运营商 (6)
  '10010.com', 'chinamobile.com', 'chinanetcenter.com', 'chinaunicom.com', 'cmpassport.com',
  'cmpay.com',

  // #银行/金融 (29)
  '800best.com', '95516.com', 'abchina.com', 'bankcomm.com', 'ccb.com', 'cebbank.com',
  'citicbank.com', 'cmbchina.com', 'cmbimg.com', 'dfcfw.com', 'eastmoney.com', 'feidee.com',
  'hexun.com', 'jimubox.com', 'lakala.com', 'lu.com', 'lufax.com', 'pingan.com', 'psbc.com',
  'renrendai.com', 'ronghub.com', 'tianyancha.com', 'unionpay.com', 'wacai.com', 'webank.com',
  'xin.com', 'xueqiu.com', 'yeepay.com', 'zhongan.com',

  // #财经媒体 (4)
  'caixin.com', 'jin10.com', 'wallstreetcn.com', 'yicai.com',

  // #房产/居住 (10)
  '5i5j.com', 'anjuke.com', 'beike.com', 'fang.com', 'ke.com', 'leju.com', 'lianjia.com',
  'soufun.com', 'xiangdao.com', 'ziroom.com',

  // #招聘 (8)
  '51job.com', 'careerintlinc.com', 'chinahr.com', 'job51.com', 'lagou.com', 'liepin.com',
  'zhaopin.com', 'zhipin.com',

  // #电商/零售 (15)
  'dangdang.com', 'dewu.com', 'dingdong.com', 'dmall.com', 'jddj.com', 'manmanbuy.com',
  'missfresh.com', 'mogujie.com', 'secoo.com', 'smzdm.com', 'vip.com', 'weidian.com',
  'xiachufang.com', 'yanxuan.com', 'yonghui.com',

  // #闲鱼/二手 (2)
  'goofish.com', 'zhuanzhuan.com',

  // #分类信息 (3)
  '58.com', '58ganji.com', 'ganji.com',

  // #物流/快递 (7)
  'deppon.com', 'jtexpress.com', 'kuaidi100.com', 'sf-express.com', 'yunda56.com', 'yundaex.com',
  'zto.com',

  // #教育 (4)
  'hujiang.com', 'xueersi.com', 'yuanfudao.com', 'zuoyebang.com',

  // #医疗 (5)
  'chunyu.mobi', 'chunyuyisheng.com', 'dxycdn.com', 'guahao.com', 'haodf.com',

  // #AI-国内 (3)
  'deepseek.com', 'iflytek.com', 'xunfei.com',

  // #游戏/体育 (9)
  '4399.com', 'dongqiudi.com', 'hupu.com', 'igamecj.com', 'mihoyo.com', 'miyoushe.com',
  'taptap.com', 'wanmei.com', 'zhibo8.cc',

  // #游戏资讯 (4)
  '3dmgame.com', 'ali213.net', 'gamersky.com', 'ngabbs.com',

  // #数字阅读 (6)
  'hongxiu.com', 'jjwxc.net', 'qimao.com', 's-reader.com', 'yuewen.com', 'zongheng.com',

  // #内容/博客 (11)
  'fandeng.com', 'igetget.com', 'izuiyou.com', 'jianshu.com', 'kkmh.com', 'kuaikanmanhua.com',
  'luojilab.com', 'raychase.net', 'scomper.me', 'sspai.com', 'zhangzishi.cc',

  // #影视资源 (9)
  'dytt8.net', 'ourdvs.com', 'xinpianchang.com', 'zimuzu.io', 'zimuzu.tv', 'zmz2019.com',
  'zmzapi.com', 'zmzapi.net', 'zmzfile.com',

  // #音频 (6)
  'kugou.com', 'kugou.net', 'lizhi.fm', 'qingting.fm', 'ximalaya.com', 'xmcdn.com',

  // #云/CDN (18)
  '21vianet.com', 'akadns.net', 'ccgslb.com', 'ccgslb.net', 'cdngslb.com', 'chinacache.com',
  'fclouddns.net', 'geilicdn.com', 'ip-cdn.com', 'ks-cdn.com', 'ksyun.com', 'ksyuncdn.com',
  'qingcloud.com', 'qiniu.com', 'staticdn.net', 'upyun.com', 'wangsu.com', 'xinnet.com',

  // #开发者-国内 (9)
  'coding.net', 'csdn.net', 'docschina.org', 'gitcode.com', 'gitee.com', 'nim-lang-cn.org',
  'oschina.net', 'seafile.com', 'segmentfault.com',

  // #学术-国内 (2)
  'cnki.net', 'cqvip.com',

  // #词典/笔记 (11)
  'eudic.net', 'frdic.com', 'godic.net', 'iciba.com', 'jidian.im', 'lanhuapp.com', 'mubu.com',
  'processon.com', 'shimo.im', 'wps.com', 'yinxiang.com',

  // #工具 (13)
  'air-matters.com', 'air-matters.io', 'b612.net', 'infinitynewtab.com', 'ip.la', 'ipip.net',
  'loli.net', 'moji.com', 'sm.ms', 'snapdrop.net', 'todesk.com', 'wondershare.com', 'xunlei.com',

  // #应用商店 (2)
  'anzhi.com', 'coolapk.com',

  // #汽车/制造 (23)
  'bitauto.com', 'byd.com', 'changhe.com', 'changhong.com', 'che168.com', 'chery.com', 'dji.com',
  'geely.com', 'gree.com', 'guazi.com', 'haier.com', 'hisense.com', 'inspur.com', 'konka.com',
  'lixiang.com', 'midea.com', 'nio.com', 'renrenche.com', 'skyworth.com', 'taoche.com', 'tcl.com',
  'xiaopeng.com', 'yiche.com',

  // #PT/影音社区 (27)
  'awesome-hd.me', 'beitaichufang.com', 'broadcasthe.net', 'chdbits.co', 'classix-unlimited.co.uk',
  'empornium.me', 'gazellegames.net', 'hdbits.org', 'hdchina.org', 'hdhome.org', 'hdsky.me',
  'icetorrent.org', 'jpopsuki.eu', 'morethan.tv', 'myanonamouse.net', 'nanyangpt.com', 'ncore.cc',
  'open.cd', 'ourbits.club', 'passthepopcorn.me', 'privatehd.to', 'pterclub.com', 'redacted.ch',
  'springsunday.net', 'tjupt.org', 'totheglory.im', 'zhuihd.com',

  // #境外可直连-学术 (53)
  'acs.org', 'aip.org', 'ams.org', 'annualreviews.org', 'aps.org', 'ascelibrary.org', 'asm.org',
  'asme.org', 'astm.org', 'bmj.com', 'cambridge.org', 'cas.org', 'clarivate.com', 'ebscohost.com',
  'emerald.com', 'engineeringvillage.com', 'icevirtuallibrary.com', 'ieee.org', 'imf.org',
  'iop.org', 'jamanetwork.com', 'jhu.edu', 'jstor.org', 'karger.com', 'libguides.com', 'mpg.de',
  'myilibrary.com', 'nature.com', 'oecd-ilibrary.org', 'osapublishing.org', 'oup.com', 'ovid.com',
  'oxfordartonline.com', 'oxfordbibliographies.com', 'oxfordmusiconline.com', 'pnas.org',
  'proquest.com', 'rsc.org', 'sagepub.com', 'sciencedirect.com', 'scopus.com', 'siam.org',
  'spiedigitallibrary.org', 'springer.com', 'springerlink.com', 'tandfonline.com', 'un.org',
  'uni-bielefeld.de', 'webofknowledge.com', 'westlaw.com', 'wiley.com', 'worldbank.org',
  'worldscientific.com',

  // #境外可直连-其他 (30)
  'accuweather.com', 'acm.org', 'amd.com', 'booking.com', 'bstatic.com', 'gandi.net',
  'ipv6-test.com', 'java.com', 'kaspersky-labs.com', 'netspeedtestmaster.com',
  'network-test.debian.org', 'ntp.org', 'nvidia.com', 'oracle.com', 'paypal.com',
  'paypalobjects.com', 'qualcomm.com', 'redhat.com', 'steam-chat.com', 'steamcdn-a.akamaihd.net',
  'steamcontent.com', 'steamgames.com', 'steampowered.com', 'steamstat.us', 'steamusercontent.com',
  'test-ipv6.com', 'udacity.com', 'vmware.com', 'weather.com', 'whatismyip.com',

  // #特殊/本地 (3)
  'cn', 'lan', 'local',

  // #自有域名 (1)
  'uuuio.com',

  // #其他 (47)
  '21cn.com', '2345.com', '343480.com', '51ym.me', '71.am.com', '8686c.com', 'aicoinstorge.com',
  'allawntech.com', 'baduziyuan.com', 'biyao.com', 'bjango.com', 'camera360.com', 'ch.com',
  'chinaso.com', 'chua.pro', 'chuimg.com', 'com-hs-hkdy.com', 'czybjz.com', 'dandanzan.com',
  'feng.com', 'fengkongcloud.com', 'fjhps.com', 'h3c.com', 'haidilao.com', 'hikvision.com',
  'hostbuf.com', 'i.cloud.com', 'ithome.com', 'jstucdn.com', 'keepcdn.com', 'keepfrds.com',
  'ksosoft.com', 'kuyunbo.club', 'liangxin.com', 'luckincoffee.com', 'madsrevolution.net',
  'mixue.com', 'moke.com', 'ruguoapp.com', 'sandai.net', 'snwx.com', 'tfogc.com', 'uning.com',
  'wnl.com', 'yonyou.com', 'zhongke.com', 'zhubajie.com',
];

// 直连：精确域名匹配（境内 CDN 专用主机名）
const DIRECT_DOMAIN = [
  'blzddist1-a.akamaihd.net', 'download.jetbrains.com', 'file-igamecj.akamaized.net',
  'images-cn.ssl-images-amazon.com', 'officecdn-microsoft-com.akamaized.net',
  'speedtest.macpaw.com', 'www-cdn.icloud.com.akadns.net',
];

// PROXY_SUFFIX：域名后缀匹配（按服务/厂商分类，块内按字母序）
const PROXY_SUFFIX = [
  // #Google (102)
  '1e100.net', 'abc.xyz', 'ad-delivery.net', 'admob.com', 'agones.dev', 'ampproject.org',
  'android.com', 'androidify.com', 'angular.dev', 'angular.io', 'angularjs.org', 'apigee.com',
  'appspot.com', 'autodraw.com', 'bazel.build', 'capitalg.com', 'chrome.com', 'chromebook.com',
  'chromecast.com', 'chromeexperiments.com', 'chromestatus.com', 'chromium.org',
  'chronicle.security', 'cloudfunctions.net', 'crashlytics.com', 'creativelab5.com', 'dart.dev',
  'deepmind.com', 'dialogflow.com', 'doubleclick.net', 'dremel.org', 'envoyproxy.io',
  'feedburner.com', 'firebaseapp.com', 'firebaseio.com', 'fitbit.com', 'flutter.dev', 'forms.gle',
  'g.co', 'getmdl.io', 'getoutline.org', 'getpricetag.com', 'gmail.com', 'gmodules.com', 'go.dev',
  'goo.gl', 'goog', 'google-analytics.com', 'google.ca', 'google.co.in', 'google.co.jp',
  'google.co.kr', 'google.co.th', 'google.co.uk', 'google.com', 'google.com.au', 'google.com.hk',
  'google.com.sg', 'google.com.tw', 'google.de', 'google.fr', 'googleadservices.com',
  'googleapis.com', 'googlesyndication.com', 'googletagmanager.com', 'googleusercontent.com',
  'googlezip.net', 'grpc.io', 'gstatic.com', 'gv.com', 'gwtproject.org', 'istio.io',
  'itasoftware.com', 'kaggle.com', 'knative.dev', 'kubernetes.io', 'looker.com',
  'madewithcode.com', 'mandiant.com', 'material.io', 'nest.com', 'orbitera.com',
  'polymer-project.org', 'protobuf.dev', 'recaptcha.net', 'spinnaker.io', 'synergyse.com',
  'tensorflow.org', 'tfhub.dev', 'tiltbrush.com', 'virustotal.com', 'waveprotocol.org',
  'waymo.com', 'waze.com', 'web.app', 'web.dev', 'webmproject.org', 'webrtc.org',
  'whatbrowser.org', 'widevine.com', 'x.company', 'xn--ngstr-lra8j.com',

  // #Googleplay (13)
  'android.clients.google.com', 'app-measurement.com', 'ggpht.com', 'gvt0.com', 'gvt1.com',
  'gvt1.net', 'gvt2.com', 'gvt2.net', 'gvt3.com', 'gvt3.net', 'gvt6.com', 'gvt9.com',
  'play.google.com',

  // #YouTube (4)
  'googlevideo.com', 'youtu.be', 'yt.be', 'ytimg.com',

  // #TikTok (8)
  'ibytedtos.com', 'ibyteimg.com', 'muscdn.com', 'musical.ly', 'tiktok.com', 'tiktokcdn-us.com', 'tiktokcdn.com', 'tiktokv.com',

  // #Reddit (4)
  'redd.it', 'reddit.com', 'redditmedia.com', 'redditstatic.com',

  // #AI-OpenAI (16)
  'algolia.net', 'chat.openai.com.cdn.cloudflare.net', 'chatgpt.com', 'chatgpt.livekit.cloud',
  'client-api.arkoselabs.com', 'host.livekit.cloud', 'oaistatic.com', 'oaiusercontent.com',
  'openai-api.arkoselabs.com', 'openai.com', 'openaiapi-site.azureedge.net',
  'openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net', 'openaicom.imgix.net',
  'openaicomproductionae4b.blob.core.windows.net', 'production-openaicom-storage.azureedge.net',
  'turn.livekit.cloud',

  // #AI-Claude (12)
  'anthropic-cdn.com', 'anthropic.cloud', 'anthropic.com', 'anthropiccdn.com',
  'anthropicsystem.com', 'clau.de', 'claude.ai', 'claude.com', 'claude.site',
  'claudemcpclient.com', 'claudemcpcontent.com', 'claudeusercontent.com',

  // #AI-Gemini (2)
  'aistudio.google.com', 'gemini.google.com',

  // #AI-其他 (40)
  'character.ai', 'chat.com', 'chatpdf.com', 'civitai.com', 'cohere.ai', 'cohere.com', 'coze.com',
  'cursor.com', 'cursor.sh', 'deepinfra.com', 'elevenlabs.io', 'fireworks.ai', 'flowgpt.com',
  'grok.com', 'groq.com', 'huggingface.co', 'jan.ai', 'leonardo.ai', 'lexica.art', 'lmarena.ai',
  'meta.ai', 'midjourney.com', 'mistral.ai', 'openart.ai', 'openrouter.ai', 'perplexity.ai',
  'poe.com', 'popai.pro', 'pplx.ai', 'prompthero.com', 'replicate.com', 'runwayml.com', 'sider.ai',
  'sora.com', 'stability.ai', 'suno.ai', 'together.ai', 'wombo.ai', 'x.ai', 'you.com',

  // #Microsoft-Bing (3)
  'bing.com', 'copilot.bing.com', 'onedrive.live.com',

  // #社交 (64)
  'bsky.app', 'bsky.network', 'bsky.social', 'cdninstagram.com', 'clubhouse.com',
  'clubhouse.pubnub.com', 'clubhouseapi.com', 'daum.net', 'discord.com', 'discord.gg',
  'discordapp.com', 'disqus.com', 'fb.com', 'fb.me', 'fbcdn.net', 'fbsbx.com', 'instagr.am',
  'instagram.com', 'joinclubhouse.com', 'kakao.com', 'licdn.com', 'line-apps.com', 'line-cdn.net',
  'line-scdn.net', 'line.me', 'line.naver.jp', 'linkedin.com', 'linktr.ee', 'mastodon.social',
  'messenger.com', 'meta.com', 'mewe.com', 'naver.com', 'ok.ru', 'pinimg.com', 'pinterest.ca',
  'pinterest.com', 'pixnet.net', 'plurk.com', 'quora.com', 'quoracdn.net', 'signal.me',
  'signal.org', 'snapchat.com', 't.co', 't.me', 'tapbots.com', 'tdesktop.com', 'telegra.ph',
  'telegram.me', 'telegram.org', 'telesco.pe', 'threads.com', 'threads.net', 'tiny.cc',
  'tinyurl.com', 'tumblr.com', 'twimg.com', 'twitter.com', 'viber.com', 'whatsapp.com',
  'whatsapp.net', 'whispersystems.org', 'x.com',

  // #社区/论坛 (18)
  '6park.com', '9gag.com', 'ao3.org', 'archiveofourown.org', 'ck101.com', 'dcard.tw', 'fandom.com',
  'goodreads.com', 'hkgolden.com', 'hostloc.com', 'knowyourmeme.com', 'lihkg.com', 'linux.do',
  'metafilter.com', 'mitbbs.com', 'nodeseek.com', 'ptt.cc', 'wattpad.com',

  // #流媒体/二次元 (44)
  'bamgrid.com', 'bandcamp.com', 'boomplay.com', 'buzzsprout.com', 'castbox.fm', 'crunchyroll.com',
  'dailymotion.com', 'deezer.com', 'disneyplus.com', 'dmm.com', 'fast.com', 'fc2.com',
  'genius.com', 'hbo.com', 'hbomax.com', 'hulu.com', 'hulustream.com', 'max.com', 'mixcloud.com',
  'mubi.com', 'netflix.com', 'nflxext.com', 'nflxso.net', 'nflxvideo.net', 'nicovideo.jp',
  'nimg.jp', 'odysee.com', 'overcast.fm', 'pandora.com', 'pixiv.net', 'podbean.com',
  'primevideo.com', 'pv-cdn.net', 'pximg.net', 'rumble.com', 'scdn.co', 'sndcdn.com',
  'soundcloud.com', 'spotify.com', 'tenor.com', 'twitch.tv', 'vevo.com', 'vimeo.com',
  'vimeocdn.com',

  // #维基/百科 (7)
  'wikibooks.org', 'wikidata.org', 'wikimedia.org', 'wikinews.org', 'wikipedia.com',
  'wikipedia.org', 'wikiquote.org',

  // #游戏 (3)
  'battle.net', 'blizzard.com', 'oculus.com',

  // #游戏-国际 (16)
  'ea.com', 'epicgames.com', 'gamer.com.tw', 'gog.com', 'itch.io', 'mahjongsoul.com',
  'minecraft.net', 'nintendo.com', 'paimon.moe', 'pcgamesn.com', 'playstation.com',
  'riotgames.com', 'roblox.com', 'tanks.gg', 'ubi.com', 'wowhead.com',

  // #图床/内容 (8)
  'catbox.moe', 'flickr.com', 'gravatar.com', 'imageshack.us', 'imgur.com', 'openstreetmap.org',
  'raindrop.io', 'staticflickr.com',

  // #开发者/技术 (100)
  'akamai.net', 'akamaihd.net', 'amazon.com', 'amazonaws.com', 'ap3.agora.io', 'api.statsig.com',
  'apple-relay.akamaized.net', 'apple-relay.fastly-edge.com', 'atlassian.net', 'auth0.com',
  'bit.ly', 'bitbucket.org', 'blog.com', 'blogcdn.com', 'blogger.com', 'blogsmithmedia.com',
  'box.net', 'brave.com', 'browser-intake-datadoghq.com', 'cdn.cloudflare.net', 'cl.ly',
  'cloudflare-ipfs.com', 'cloudflare.com', 'cloudflaremirrors.com', 'cloudfront.net',
  'cocoapods.org', 'dnsimple.com', 'dnsleak.com', 'dnsleaktest.com', 'docker.com', 'docker.io',
  'dribbble.com', 'dropbox.com', 'dropboxstatic.com', 'dropboxusercontent.com', 'duckduckgo.com',
  'edgecastcdn.net', 'events.statsigapi.net', 'fabric.io', 'fastly.net', 'featuregates.org',
  'gcr.io', 'git.io', 'github.com', 'github.io', 'githubassets.com', 'githubcopilot.com',
  'githubusercontent.com', 'gitlab.com', 'gitlab.net', 'godaddy.com', 'godoc.org', 'golang.org',
  'greasyfork.org', 'hackmd.io', 'ift.tt', 'intercom.io', 'intercomcdn.com', 'ipfs.io', 'j.mp',
  'jsdelivr.net', 'jshint.com', 'launchdarkly.com', 'linode.com', 'medium.com', 'mega.io',
  'mega.nz', 'name.com', 'netlify.app', 'netlify.com', 'npm.community', 'npmjs.org',
  'o33249.ingest.sentry.io', 'openwrt.org', 'ow.ly', 'page.link', 'proton.me', 'protonmail.com',
  'protonvpn.com', 'putty.org', 'qbittorrent.org', 'raw.githack.com', 'rsshub.app', 'segment.io',
  'sentry.io', 'sleazyfork.org', 'sourceforge.net', 'squarespace.com', 'ssl-images-amazon.com',
  'sstatic.net', 'stackoverflow.com', 'startpage.com', 'static.cloudflareinsights.com',
  'stripe.com', 'tortoisesvn.net', 'vercel.app', 'vercel.com', 'wordpress.com', 'workers.dev',
  'wp.com',

  // #生产力/协作 (12)
  'adobe.com', 'asana.com', 'canva.com', 'evernote.com', 'figma.com', 'grammarly.com', 'miro.com',
  'notion.so', 'slack.com', 'snapseed.com', 'trello.com', 'typora.io',

  // #学习 (18)
  'arxiv.org', 'codecademy.com', 'coursera.org', 'duolingo.com', 'edx.org', 'issuu.com',
  'khanacademy.org', 'kobo.com', 'leetcode.com', 'overleaf.com', 'quizlet.com', 'sci-hub.ru',
  'sci-hub.se', 'scratch.mit.edu', 'scribd.com', 'skillshare.com', 'slideshare.net', 'udemy.com',

  // #旅行/住宿 (9)
  'agoda.com', 'airbnb.com', 'expedia.com', 'hotels.com', 'kayak.com', 'lyft.com',
  'skyscanner.net', 'tripadvisor.com', 'uber.com',

  // #购物/海淘 (15)
  'aliexpress.com', 'amazon.co.jp', 'carousell.com.hk', 'ebay.com', 'etsy.com', 'gumroad.com',
  'mercari.com', 'mercari.jp', 'play-asia.com', 'redbubble.com', 'shein.com', 'shopee.tw',
  'temu.com', 'wish.com', 'yesasia.com',

  // #币圈 (29)
  'binance.com', 'binance.org', 'bitfinex.com', 'bybit.com', 'coinbase.com', 'coingecko.com',
  'coinmarketcap.com', 'crypto.com', 'etherscan.io', 'gate.io', 'huobi.com', 'kraken.com',
  'kucoin.com', 'ledger.com', 'metamask.io', 'mexc.com', 'okex.com', 'okx.com', 'opensea.io',
  'pancakeswap.finance', 'poloniex.com', 'solana.com', 'solscan.io', 'token.im', 'tronscan.org',
  'trustwallet.com', 'uniswap.org', 'upbit.com', 'walletconnect.org',

  // #安卓应用市场 (4)
  'apkmirror.com', 'apkpure.com', 'f-droid.org', 'xda-developers.com',

  // #资讯/新闻 (47)
  'aljazeera.com', 'apnews.com', 'axios.com', 'bbc.co.uk', 'bbc.com', 'bbci.co.uk',
  'bleepingcomputer.com', 'bloomberg.com', 'businessinsider.com', 'cbsnews.com', 'cnn.com',
  'dailymail.co.uk', 'dw.com', 'economist.com', 'engadget.com', 'forbes.com', 'ft.com',
  'ftchinese.com', 'huffpost.com', 'investing.com', 'nbcnews.com', 'newsweek.com', 'newyorker.com',
  'nikkei.com', 'nytimes.com', 'nytimg.com', 'reuters.com', 'reutersmedia.net', 'rfa.org',
  'rfi.fr', 'sciencemag.org', 'scmp.com', 'substack.com', 'swissinfo.ch', 'theatlantic.com',
  'thediplomat.com', 'theguardian.com', 'theintercept.com', 'time.com', 'tradingview.com',
  'v2ex.com', 'voanews.com', 'vox.com', 'washingtonpost.com', 'wsj.com', 'wsj.net',
  'zerohedge.com',

  // #资讯-科技 (8)
  'arstechnica.com', 'gizmodo.com', 'mashable.com', 'techcrunch.com', 'thenextweb.com',
  'theverge.com', 'wired.com', 'ycombinator.com',

  // #安全/VPN (20)
  'browserleaks.com', 'browserleaks.org', 'certificate-transparency.org', 'digicert.com',
  'eurekavpt.com', 'expressvpn.com', 'identrust.com', 'ipleak.net', 'nordvpn.com', 'observeit.net',
  'openvpn.net', 'perfect-privacy.com', 'surfshark.com', 'symauth.com', 'symcb.com', 'symcd.com',
  'teamviewer.com', 'ubnt.com', 'vpnunlimited.com', 'whoer.net',

  // #成人/看片 (73)
  '18comic.org', '91porn.com', '9xbuddy.com', 'avgle.com', 'beeg.com', 'brazzers.com',
  'camwhores.tv', 'chaturbate.com', 'danbooru.donmai.us', 'e-hentai.org', 'e621.net',
  'eporner.com', 'erome.com', 'exhentai.org', 'gelbooru.com', 'hanime.tv', 'hanime1.com',
  'hanimeone.me', 'hitomi.la', 'jable.tv', 'jav.com', 'javbus.com', 'javchu.com', 'javdb.com',
  'javlibrary.com', 'kali.download', 'kat.cr', 'konachan.com', 'livejasmin.com', 'm-team.cc',
  'manyvids.com', 'megaupload.com', 'missav.com', 'missav.ws', 'missav.ai', 'missav.tube', 'motherless.com', 'myfreecams.com',
  'naughtyamerica.com', 'netflav.com', 'nhentai.net', 'onejav.com', 'onlyfans.com', 'phncdn.com',
  'picacomic.com', 'playboy.com', 'pornhd.com', 'pornhub.com', 'realitykings.com', 'redtube.com',
  'rule34.xxx', 'sankakucomplex.com', 'sehuatang.net', 'sex.com', 'sex8.cc', 'sis001.com',
  'south-plus.net', 'spankbang.com', 'streamate.com', 'stripchat.com', 't66y.com',
  'thepiratebay.org', 'tnaflix.com', 'tube8.com', 'vporn.com', 'wnacg.org', 'x-art.com',
  'xhamster.com', 'xnxx.com', 'xtube.com', 'xv-ru.com', 'xvideos-cdn.com', 'xvideos.com',
  'yande.re', 'youjizz.com', 'youporn.com',

  // #其他 (13)
  'archive.org', 'cdn.angruo.com', 'debug.com', 'kenengba.com', 'lithium.com', 'mobile01.com',
  'modmyi.com', 'patreon.com', 'patreonusercontent.com', 'pinboard.in', 'shattered.io', 'whrq.net',
  'zoom.us',
];

// 代理：精确域名匹配（API/CDN 精确主机名，避免后缀误伤）
const PROXY_DOMAIN = [
  'api.statsig.com', 'browser-intake-datadoghq.com', 'chat.openai.com.cdn.cloudflare.net',
  'o33249.ingest.sentry.io', 'openai-api.arkoselabs.com',
  'openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net',
  'openaicomproductionae4b.blob.core.windows.net', 'production-openaicom-storage.azureedge.net',
  'static.cloudflareinsights.com', 'copilot.bing.com', 'cdn.angruo.com',
];

// 代理例外：优先于直连父域判断（即使父域直连也强制代理）
const PROXY_OVERRIDE = [
  'copilot.microsoft.com', 'store.steampowered.com', 'api.steampowered.com', 'steamcommunity.com',
  'steamstatic.com', 'onedrive.com', 'futunn.com', 'futu5.com', 'futu.cn', 'futubull.cn',
  'moomoo.com', 'itiger.com', 'tigerbrokers.com', 'tigerbbs.cn', 'longbridge.com',
  'longbridgeapp.com', 'longportapp.com', 'longportapp.cn', 'trade.longportapp.com',
  'openapi.longbridge.cn', 'openapi-quote.longbridge.cn', 'openapi-trade.longbridge.cn',
];

// 代理：域名关键字匹配（包含即代理）
const PROXY_KEYWORD = [
  'blogspot', 'facebook', 'gmail', 'google', 'instagram', 'missav', 'openaicom-api', 'pixiv', 'twitter',
  'youtube',
];

// 代理：IP 段匹配（域名解析结果落入这些段，一律强制代理，防止 CDN 解析结果因污染/误判落错方向）
const PROXY_IP_CIDR = [
  // #Google 主段
  '108.177.0.0/17', '142.250.0.0/15', '172.217.0.0/16', '173.194.0.0/16', '209.85.128.0/17',
  '216.239.32.0/19', '216.58.0.0/17', '216.58.192.0/19', '64.233.160.0/19', '66.102.0.0/20',
  '66.249.64.0/19', '72.14.192.0/18', '74.125.0.0/16',

  // #Google Cloud
  '34.0.0.0/15', '34.2.0.0/16', '34.3.0.0/16', '34.4.0.0/16', '34.64.0.0/10', '35.184.0.0/13',
  '35.192.0.0/12', '35.208.0.0/12', '35.224.0.0/12', '35.240.0.0/13', '8.34.208.0/20',
  '8.35.192.0/19',

  // #Google DNS
  '8.8.4.0/24', '8.8.8.0/24',

  // #Telegram
  '109.239.140.0/24', '149.154.160.0/20', '91.108.12.0/22', '91.108.16.0/22', '91.108.4.0/22',
  '91.108.56.0/22', '91.108.8.0/22',

  // #Anthropic-Claude
  '160.79.104.0/21',
];

















function requiredConfig(env) {
  const hy2 = String(env.HY2 || '').trim();
  const vless = String(env.VLESS || '').trim();
  if (!hy2 && !vless) {
    throw new Error('HY2 或 VLESS 至少配置一个 Worker Secret/变量');
  }
  return {
    hy2,
    vless,
    dashboardUrl: String(env.DASHBOARD_URL || DEFAULT_DASHBOARD),
    ruleServer: String(env.RULE_SERVER || DEFAULT_RULE_SERVER).replace(/\/+$/, ''),
    clashApiListen: String(env.CLASH_API_LISTEN || '0.0.0.0:9090'),
    clashApiSecret: String(env.CLASH_API_SECRET || ''),
  };
}

function decodeSafe(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

// ── 端口跳跃解析：单端口/端口段/逗号分隔多段，语法与原实现完全一致 ──
function parsePortList(portPart) {
  const tokens = String(portPart || '443')
    .split(',')
    .map(x => x.trim())
    .filter(Boolean);
  if (!tokens.length) throw new Error('端口不能为空');

  const first = tokens[0].includes('-') ? tokens[0].split('-')[0] : tokens[0];
  const firstPort = Number(first);
  if (!Number.isInteger(firstPort) || firstPort < 1 || firstPort > 65535) {
    throw new Error(`无效端口: ${first}`);
  }

  for (const token of tokens) {
    const m = /^(\d+)(?:-(\d+))?$/.exec(token);
    if (!m) throw new Error(`无效端口/端口段: ${token}`);
    const a = Number(m[1]);
    const b = m[2] ? Number(m[2]) : a;
    if (a < 1 || a > 65535 || b < 1 || b > 65535 || b < a) {
      throw new Error(`无效端口/端口段: ${token}`);
    }
  }

  const hasRange = tokens.some(x => x.includes('-'));
  const hasMultiple = tokens.length > 1;
  // sing-box 端口段/多段用冒号 ":" 分隔 (server_ports: ["20000:20100"])
  const serverPorts = (hasRange || hasMultiple)
    ? tokens.map(x => x.replace('-', ':'))
    : null;

  return { firstPort, serverPorts, rawPorts: tokens };
}

function parseHostPort(rawHostPort) {
  const hp = rawHostPort.replace(/\/$/, '');
  if (hp.startsWith('[')) {
    const end = hp.indexOf(']');
    if (end === -1) throw new Error('IPv6 地址缺少 ]');
    const host = hp.slice(1, end);
    const portPart = hp.slice(end + 1).replace(/^:/, '') || '443';
    return { server: host, portPart };
  }
  const colon = hp.lastIndexOf(':');
  if (colon === -1) return { server: hp, portPart: '443' };
  return { server: hp.slice(0, colon), portPart: hp.slice(colon + 1) || '443' };
}

function parseHysteria2(raw, fallbackName = 'Hysteria2') {
  if (!raw.startsWith('hysteria2://') && !raw.startsWith('hy2://')) {
    throw new Error('无效 Hysteria2 URL');
  }

  const schemeLen = raw.startsWith('hy2://') ? 6 : 12;
  const withoutScheme = raw.slice(schemeLen);
  const hashIndex = withoutScheme.indexOf('#');
  const withoutHash = hashIndex >= 0 ? withoutScheme.slice(0, hashIndex) : withoutScheme;
  const hash = hashIndex >= 0 ? withoutScheme.slice(hashIndex + 1) : '';
  const qIndex = withoutHash.indexOf('?');
  const beforeQuery = qIndex >= 0 ? withoutHash.slice(0, qIndex) : withoutHash;
  const query = qIndex >= 0 ? withoutHash.slice(qIndex + 1) : '';

  const at = beforeQuery.lastIndexOf('@');
  if (at <= 0) throw new Error('Hysteria2 URL 缺少 password@host');

  const password = decodeSafe(beforeQuery.slice(0, at));
  const { server, portPart } = parseHostPort(beforeQuery.slice(at + 1));
  const q = new URLSearchParams(query);
  const name = decodeSafe(hash || fallbackName);
  const { firstPort, serverPorts, rawPorts } = parsePortList(portPart);

  const obfsType = q.get('obfs') || '';
  const obfsPassword = q.get('obfs-password') || '';
  const alpn = (q.get('alpn') || 'h3')
    .split(',').map(s => s.trim()).filter(Boolean);

  return {
    type: 'hysteria2',
    name,
    server,
    server_port: firstPort,
    ...(serverPorts ? { server_ports: serverPorts, hop_interval: q.get('hop-interval') || '300s' } : {}),
    password,
    ...(obfsType ? { obfs: { type: obfsType, password: obfsPassword } } : {}),
    tls: {
      enabled: true,
      server_name: q.get('sni') || server,
      ...(q.get('insecure') === '1' ? { insecure: true } : {}),
      alpn,
    },
    _rawPorts: rawPorts,
  };
}

function parseVless(raw, fallbackName = 'VLESS') {
  if (!raw.startsWith('vless://')) throw new Error('无效 VLESS URL');

  const url = new URL(raw);
  const uuid = decodeSafe(url.username);
  const server = url.hostname;
  const serverPort = Number(url.port || '443');
  if (!uuid || !server || !Number.isInteger(serverPort) || serverPort < 1 || serverPort > 65535) {
    throw new Error('VLESS URL 参数无效');
  }

  const p = url.searchParams;
  const transportType = (p.get('type') || p.get('network') || 'tcp').toLowerCase();
  const security = (p.get('security') || 'tls').toLowerCase();
  const tag = decodeSafe(url.hash ? url.hash.slice(1) : fallbackName);

  const transport = {};
  if (transportType === 'ws') {
    transport.type = 'ws';
    transport.path = p.get('path') || '/';
    const host = p.get('host');
    if (host) transport.headers = { Host: host };
    const earlyData = Number(p.get('ed') || p.get('maxEarlyData') || 0);
    const earlyDataHeader = p.get('eh') || p.get('earlyDataHeaderName') || '';
    if (Number.isInteger(earlyData) && earlyData > 0) transport.max_early_data = earlyData;
    if (earlyDataHeader) transport.early_data_header_name = earlyDataHeader;
  } else if (transportType === 'grpc') {
    transport.type = 'grpc';
    transport.service_name = p.get('serviceName') || p.get('service_name') || '';
  } else if (transportType === 'http' || transportType === 'h2') {
    transport.type = 'http';
    transport.path = p.get('path') || '/';
    const host = p.get('host');
    if (host) transport.host = [host];
  } else if (transportType !== 'tcp') {
    throw new Error(`暂不支持 VLESS transport=${transportType}`);
  }

  // UDP 放开 (2026-08-25, 与 server.py 对齐): 原写死 network:'tcp' 把 QUIC/UDP 掐了,
  // 导致 Play/TikTok 下载尾部校验(QUIC)卡 99%。去掉后 sing-box 默认 tcp+udp。
  const outbound = {
    type: 'vless',
    tag,
    server,
    server_port: serverPort,
    uuid,
    ...(p.get('flow') ? { flow: p.get('flow') } : {}),
    ...(p.get('packet-encoding') ? { packet_encoding: p.get('packet-encoding') } : {}),
  };

  if (security !== 'none' && security !== 'tls' && security !== 'reality') {
    throw new Error(`暂不支持 VLESS security=${security}`);
  }

  if (security === 'tls' || security === 'reality') {
    const tls = {
      enabled: true,
      server_name: p.get('sni') || p.get('host') || server,
      ...(p.get('allowInsecure') === '1' || p.get('insecure') === '1' ? { insecure: true } : {}),
      ...(p.get('alpn') ? { alpn: p.get('alpn').split(',').map(s => s.trim()).filter(Boolean) } : {}),
    };

    const fingerprint = p.get('fp') || p.get('fingerprint') || '';
    if (fingerprint) tls.utls = { enabled: true, fingerprint };

    if (security === 'reality') {
      const pbk = p.get('pbk');
      const sid = p.get('sid') || p.get('shortId') || '';
      if (!pbk) throw new Error('VLESS Reality URL 缺少 pbk');
      tls.reality = {
        enabled: true,
        public_key: pbk,
        ...(sid ? { short_id: sid } : {}),
      };
    }
    outbound.tls = tls;
  }

  if (Object.keys(transport).length) outbound.transport = transport;
  return { type: 'vless', ...outbound, _transportType: transportType };
}

function makeNodeConfigs(cfg) {
  const nodes = [];
  if (cfg.hy2) nodes.push(parseHysteria2(cfg.hy2, 'HY2'));
  if (cfg.vless) nodes.push(parseVless(cfg.vless, 'VLESS'));
  if (!nodes.length) throw new Error('没有可用节点');
  return nodes;
}

function sanitizeTag(tag, prefix) {
  const x = String(tag || '')
    .replace(/[^A-Za-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return `${prefix}-${x || 'node'}`.slice(0, 96);
}

function buildOutbounds(nodes) {
  const translated = nodes.map((n, i) => {
    const tag = sanitizeTag(n.name || n.tag || `node-${i + 1}`, n.type);
    const { name, tag: _tag, _rawPorts, _transportType, ...rest } = n;
    return { ...rest, tag };
  });
  const nodeTags = translated.map(n => n.tag);
  const outbounds = [...translated];
  outbounds.push({ type: 'selector', tag: 'proxy', outbounds: nodeTags, default: nodeTags[0] });
  outbounds.push({ type: 'selector', tag: 'global', outbounds: ['proxy', 'direct', 'block'], default: 'proxy' });
  outbounds.push({ type: 'direct', tag: 'direct' });
  outbounds.push({ type: 'block', tag: 'block' });
  return { translated, outbounds };
}

// ═════════════════════════════════════════════════════════════
// sing-box 配置生成（纯硬编码，无 rule_set 引用）
// ═════════════════════════════════════════════════════════════
function buildSingbox(env, routerMode) {
  const cfg = requiredConfig(env);
  const nodes = makeNodeConfigs(cfg);
  const { outbounds } = buildOutbounds(nodes);
  const proxyTag = 'proxy';
  const nodeHosts = [...new Set(nodes.map(n => n.server).filter(Boolean))];

  // DNS 分层：bootstrap(仅解析节点自身host) / direct(自建DoH) / proxy(经代理转发) / fakeip
  const dnsRules = [
    { clash_mode: 'direct', action: 'route', server: 'dns-direct' },
    { clash_mode: 'global', action: 'route', server: 'dns-proxy' },
    { domain: nodeHosts, server: 'dns-bootstrap' },
    { domain_suffix: PROXY_OVERRIDE, query_type: ['A', 'AAAA'], server: 'dns-fakeip' },
    { domain_suffix: PROXY_OVERRIDE, server: 'dns-proxy' },
    { domain_suffix: DIRECT_SUFFIX, server: 'dns-direct' },
    { domain: DIRECT_DOMAIN, server: 'dns-direct' },
    { domain_suffix: PROXY_SUFFIX, query_type: ['A', 'AAAA'], server: 'dns-fakeip' },
    { domain_suffix: PROXY_SUFFIX, server: 'dns-proxy' },
    { domain: PROXY_DOMAIN, query_type: ['A', 'AAAA'], server: 'dns-fakeip' },
    { domain: PROXY_DOMAIN, server: 'dns-proxy' },
    { domain_keyword: PROXY_KEYWORD, query_type: ['A', 'AAAA'], server: 'dns-fakeip' },
    { domain_keyword: PROXY_KEYWORD, server: 'dns-proxy' },
    // geosite-cn 国内域名大全: 未硬编码的国内域名(字节新CDN等) DNS 走阿里, 出口国内 + geoDNS 正确
    { rule_set: ['geosite-cn'], server: 'dns-direct' },
  ];

  const routeRules = [
    { action: 'sniff' },
    { clash_mode: 'direct', outbound: 'direct' },
    { clash_mode: 'global', outbound: proxyTag },
    { protocol: 'dns', action: 'hijack-dns' },
    { domain: nodeHosts, outbound: 'direct' },
    { domain_suffix: PROXY_OVERRIDE, outbound: proxyTag },
    { domain_suffix: DIRECT_SUFFIX, outbound: 'direct' },
    { domain: DIRECT_DOMAIN, outbound: 'direct' },
    { ip_cidr: PROXY_IP_CIDR, outbound: proxyTag },
    { domain_suffix: PROXY_SUFFIX, outbound: proxyTag },
    { domain: PROXY_DOMAIN, outbound: proxyTag },
    { domain_keyword: PROXY_KEYWORD, outbound: proxyTag },
    { ip_is_private: true, outbound: 'direct' },
    // geosite-cn 域名级国内兜底: 与 GEOIP 兜底互补(域名先判), 国内域名直接出站
    { rule_set: ['geosite-cn'], outbound: 'direct' },
    // GEOIP 兜底层: 硬编码规则没列到的域名, 按解析出的 IP 归属判断, 中国 IP 直接出站
    // (根治"漏写国内域名→误走代理": douyinpic/djicdn 这类新 CDN 子域不用再逐个手写)
    { rule_set: ['geoip-cn'], outbound: 'direct' },
  ];

  const tun = {
    type: 'tun',
    tag: 'tun-in',
    interface_name: 'singbox',
    address: ['172.19.0.1/30'],
    mtu: 9000,
    auto_route: true,
    strict_route: true,
    stack: routerMode ? 'system' : 'gvisor',
    ...(routerMode ? { auto_redirect: true } : {}),
  };

  const mixedIn = { type: 'mixed', tag: 'mixed-in', listen: '0.0.0.0', listen_port: 7890 };

  return {
    log: { level: 'warn', timestamp: true },
    http_clients: [
      // 1.14+: 远程规则集下载走直连(download_detour 已弃用, 1.16 移除)。⚠️ 不能写 detour:'direct'
      // —— 规则集下载发生在 outbound 初始化前, direct 还是空的, 会 fatal "detour to an empty direct
      // outbound makes no sense"(同 DNS 坑, 实测复现); 不带 detour 的 http_client 默认即直连。
      { tag: 'direct-client' },
    ],
    dns: {
      servers: [
        // 注意:1.12+ 里 DNS server 不带 detour 即默认走空 direct,显式写 detour:'direct' 会报
        // "detour to an empty direct outbound makes no sense" 直接 fatal。dns-bootstrap/dns-direct 保持无 detour。
        { tag: 'dns-bootstrap', type: 'udp', server: '180.184.1.1' },
        {
          tag: 'dns-direct', type: 'https', server: 'dns.alidns.com', server_port: 443,
          path: '/dns-query', domain_resolver: 'dns-bootstrap',
        },
        // dns-proxy 用 DoH(1.1.1.1:443) 走代理隧道, 而非 UDP 53：
        // ① TCP 传输, VLESS 纯 TCP 节点也稳(不依赖 UDP 中继)
        // ② 全程加密, 无明文 DNS
        // ③ 1.1.1.1 国内被墙无影响 —— 查询经隧道从海外节点出去
        { tag: 'dns-proxy', type: 'https', server: '1.1.1.1', server_port: 443, path: '/dns-query', detour: proxyTag },
        { tag: 'dns-fakeip', type: 'fakeip', inet4_range: '198.18.0.0/16' },
      ],
      rules: dnsRules,
      // final 用 dns-proxy(经代理隧道的 DoH) 而非 dns-direct(阿里DoH)：
      // 阿里公共 DoH 会处置 NSFW/赌博等域名(污染IP/SERVFAIL), 未收录即打不开;
      // 走 dns-proxy(1.1.1.1 经隧道) 任何域名都拿真IP, 兜底才可靠。
      final: 'dns-proxy',
    },
    inbounds: [tun, mixedIn],
    outbounds,
    route: {
      default_domain_resolver: 'dns-bootstrap',
      default_http_client: 'direct-client',
      auto_detect_interface: true,
      rules: routeRules,
      // geoip-cn 只依赖 IP→国家映射, 相对稳定; 自托管 mirror, 走直连下载不依赖代理
      rule_set: [{
        type: 'remote', tag: 'geosite-cn', format: 'binary',
        url: `${cfg.ruleServer}/sing/geosite/cn.srs`,
        update_interval: '24h',
      }, {
        type: 'remote', tag: 'geoip-cn', format: 'binary',
        url: `${cfg.ruleServer}/sing/geoip/cn.srs`,
        update_interval: '24h',
      }],
      final: proxyTag,
    },
    experimental: {
      cache_file: { enabled: true, store_fakeip: true },
      clash_api: {
        external_controller: cfg.clashApiListen,
        external_ui: 'ui',
        external_ui_download_url: cfg.dashboardUrl,
        external_ui_download_detour: 'direct',
        default_mode: 'rule',
        ...(cfg.clashApiSecret ? { secret: cfg.clashApiSecret } : {}),
        ...(cfg.clashApiListen !== '127.0.0.1:9090' ? { access_control_allow_private_network: true } : {}),
      },
    },
  };
}

// ═════════════════════════════════════════════════════════════
// Clash/mihomo 配置生成（纯硬编码，无 rule-providers）
// ═════════════════════════════════════════════════════════════
function buildClash(env) {
  const cfg = requiredConfig(env);
  const nodes = makeNodeConfigs(cfg);
  const proxies = nodes.map((n, i) => {
    if (n.type === 'hysteria2') {
      const p = {
        name: sanitizeTag(n.name || `HY2-${i + 1}`, 'HY2'),
        type: 'hysteria2',
        server: n.server,
        port: n.server_port,
        password: n.password,
        sni: n.tls.server_name,
        'skip-cert-verify': Boolean(n.tls.insecure),
        alpn: n.tls.alpn,
        udp: true,
      };
      if (n.server_ports) {
        // mihomo/Clash 端口段用连字符 "-" 分隔，与 sing-box 的 ":" 不同，两者均已验证正确
        p.ports = n.server_ports.map(x => x.replace(':', '-')).join(',');
        p['hop-interval'] = 300;
      }
      if (n.obfs?.type) {
        p.obfs = n.obfs.type;
        p['obfs-password'] = n.obfs.password;
      }
      return p;
    }

    const p = {
      name: sanitizeTag(n.tag || `VLESS-${i + 1}`, 'VLESS'),
      type: 'vless',
      server: n.server,
      port: n.server_port,
      uuid: n.uuid,
      udp: true,
      ...(n.flow ? { flow: n.flow } : {}),
      network: n._transportType || 'tcp',
    };

    if (n.tls) {
      p.tls = true;
      p.servername = n.tls.server_name;
      p['skip-cert-verify'] = Boolean(n.tls.insecure);
      if (n.tls.alpn?.length) p.alpn = n.tls.alpn;
      if (n.tls.utls?.fingerprint) p['client-fingerprint'] = n.tls.utls.fingerprint;
      if (n.tls.reality?.enabled) {
        p['reality-opts'] = {
          'public-key': n.tls.reality.public_key,
          ...(n.tls.reality.short_id ? { 'short-id': n.tls.reality.short_id } : {}),
        };
      }
    }

    if (n.transport?.type === 'ws') {
      p['ws-opts'] = {
        path: n.transport.path,
        headers: n.transport.headers || {},
        ...(n.transport.max_early_data ? { 'max-early-data': n.transport.max_early_data } : {}),
        ...(n.transport.early_data_header_name ? { 'early-data-header-name': n.transport.early_data_header_name } : {}),
      };
    } else if (n.transport?.type === 'grpc') {
      p['grpc-opts'] = { 'grpc-service-name': n.transport.service_name || '' };
    } else if (n.transport?.type === 'http') {
      p['http-opts'] = {
        path: n.transport.path || '/',
        ...(n.transport.host?.length ? { headers: { Host: n.transport.host[0] } } : {}),
      };
    }

    return p;
  });

  const nodeNames = proxies.map(p => p.name);
  const groups = [
    { name: 'PROXY', type: 'select', proxies: nodeNames },
    { name: 'GLOBAL', type: 'select', proxies: ['PROXY', 'DIRECT', 'REJECT'] },
  ];

  const rules = [];
  // override 必须排最前: 否则 store.steampowered.com 会被 steampowered.com(DIRECT) 先吞
  for (const d of PROXY_OVERRIDE) rules.push(`DOMAIN-SUFFIX,${d},PROXY`);
  for (const d of DIRECT_SUFFIX) rules.push(`DOMAIN-SUFFIX,${d},DIRECT`);
  for (const d of DIRECT_DOMAIN) rules.push(`DOMAIN,${d},DIRECT`);
  for (const d of PROXY_SUFFIX) rules.push(`DOMAIN-SUFFIX,${d},PROXY`);
  for (const d of PROXY_DOMAIN) rules.push(`DOMAIN,${d},PROXY`);
  for (const d of PROXY_KEYWORD) rules.push(`DOMAIN-KEYWORD,${d},PROXY`);
  for (const d of PROXY_IP_CIDR) rules.push(`IP-CIDR,${d},PROXY,no-resolve`);
  // GEOIP 兜底层: mihomo 内置 geoip 库, 解析出中国 IP 即直连, 不用把全国内域名都写进来
  rules.push('GEOIP,CN,DIRECT');
  rules.push('MATCH,PROXY'); // FINAL 兜底，仿 Shadowrocket 白名单思路

  const q = value => JSON.stringify(String(value));
  const lines = [
    'mixed-port: 7890',
    'allow-lan: true',
    "bind-address: '*'",
    'mode: rule',
    'log-level: info',
    'ipv6: false',
    'unified-delay: true',
    'profile:',
    '  store-selected: true',
    '  store-fake-ip: true',
    'dns:',
    '  enable: true',
    '  ipv6: false',
    '  enhanced-mode: fake-ip',
    '  fake-ip-range: 198.18.0.1/16',
    '  use-hosts: true',
    '  default-nameserver:',
    '    - 180.184.1.1',
    '    - 119.29.29.29',
    '  nameserver:',
    `    - ${q('https://doh.pub/dns-query')}`,
    `    - ${q('https://dns.alidns.com/dns-query')}`,
    '  fake-ip-filter:',
    '    - "*.lan"',
    '    - localhost.ptlogin2.qq.com',
    '    - dns.msftncsi.com',
    '    - "*.srv.nintendo.net"',
    '    - "*.stun.playstation.net"',
    '    - "*.xboxlive.com"',
    '    - "*.battle.net"',
    '    - "*.steamserver.net"',
    'proxies:',
  ];

  for (const p of proxies) {
    lines.push(`  - name: ${q(p.name)}`);
    lines.push(`    type: ${p.type}`);
    lines.push(`    server: ${q(p.server)}`);
    if (p.ports) {
      lines.push(`    ports: ${q(p.ports)}`, '    hop-interval: 300');
    } else {
      lines.push(`    port: ${p.port}`);
    }
    if (p.password) lines.push(`    password: ${q(p.password)}`);
    if (p.obfs) lines.push(`    obfs: ${q(p.obfs)}`, `    obfs-password: ${q(p['obfs-password'])}`);
    if (p.sni) lines.push(`    sni: ${q(p.sni)}`);
    if (p.servername) lines.push(`    servername: ${q(p.servername)}`);
    if (p.uuid) lines.push(`    uuid: ${q(p.uuid)}`);
    if (p.flow) lines.push(`    flow: ${q(p.flow)}`);
    if (p.tls) lines.push('    tls: true');
    if (p['skip-cert-verify']) lines.push('    skip-cert-verify: true');
    if (p['client-fingerprint']) lines.push(`    client-fingerprint: ${q(p['client-fingerprint'])}`);
    if (p['reality-opts']) {
      lines.push('    reality-opts:');
      lines.push(`      public-key: ${q(p['reality-opts']['public-key'])}`);
      if (p['reality-opts']['short-id']) lines.push(`      short-id: ${q(p['reality-opts']['short-id'])}`);
    }
    if (p.alpn) lines.push(`    alpn: ${JSON.stringify(p.alpn)}`);
    if (p.udp) lines.push('    udp: true');
    if (p.network) lines.push(`    network: ${q(p.network)}`);
    if (p['ws-opts']) {
      lines.push('    ws-opts:');
      lines.push(`      path: ${q(p['ws-opts'].path)}`);
      if (Object.keys(p['ws-opts'].headers).length) {
        lines.push('      headers:');
        for (const [k, v] of Object.entries(p['ws-opts'].headers)) lines.push(`        ${k}: ${q(v)}`);
      }
      if (p['ws-opts']['max-early-data']) lines.push(`      max-early-data: ${p['ws-opts']['max-early-data']}`);
      if (p['ws-opts']['early-data-header-name']) lines.push(`      early-data-header-name: ${q(p['ws-opts']['early-data-header-name'])}`);
    }
    if (p['grpc-opts']) lines.push(`    grpc-opts: ${JSON.stringify(p['grpc-opts'])}`);
    if (p['http-opts']) {
      lines.push('    http-opts:');
      lines.push(`      path: ${q(p['http-opts'].path)}`);
      if (p['http-opts'].headers) {
        lines.push('      headers:');
        for (const [k, v] of Object.entries(p['http-opts'].headers)) lines.push(`        ${k}: ${q(v)}`);
      }
    }
  }

  lines.push('proxy-groups:');
  for (const g of groups) {
    lines.push(`  - name: ${q(g.name)}`);
    lines.push(`    type: ${g.type}`);
    lines.push(`    proxies: ${JSON.stringify(g.proxies)}`);
  }

  lines.push('rules:');
  for (const r of rules) lines.push(`  - ${q(r)}`);
  return lines.join('\n') + '\n';
}

function detectTarget(request, url) {
  if (url.pathname.replace(/\/$/, '') === '/router') return 'singbox';
  const t = url.searchParams.get('target');
  if (t === 'clash') return 'clash';
  if (t === 'singbox') return 'singbox';
  if (t === 'v2rayn' || t === 'base64') return 'v2rayn';
  const ua = (request.headers.get('user-agent') || '').toLowerCase();
  if (ua.includes('clash') || ua.includes('mihomo') || ua.includes('stash') || ua.includes('clashverge')) return 'clash';
  if (ua.includes('sing-box') || ua.includes('sfa') || ua.includes('sfi') || ua.includes('sfm')) return 'singbox';
  return 'v2rayn';
}

function base64Encode(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

// v2rayN：原样返回原始订阅链接的 base64（不做任何转换）
function buildV2rayN(env) {
  const cfg = requiredConfig(env);
  const urls = [cfg.vless, cfg.hy2].filter(Boolean);
  if (!urls.length) throw new Error('没有可用节点');
  return base64Encode(urls.join('\n'));
}

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return new Response('Method Not Allowed', { status: 405 });
      }

      if (url.pathname.replace(/\/$/, '') === '/healthz') {
        return new Response(JSON.stringify({ ok: true, time: new Date().toISOString() }), {
          headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
        });
      }

      // 订阅地址 = 短子域 + 随机 token 路径; 只有 /<TOKEN> 返回订阅, 其余一律 404(防暴露)
      const cleanPath = url.pathname.replace(/\/+$/, '');
      const token = String(env.TOKEN || '').trim();
      if (!token || cleanPath !== '/' + token) {
        return new Response('Not Found', { status: 404 });
      }

      const target = detectTarget(request, url);
      if (target === 'clash') {
        const body = buildClash(env);
        return new Response(request.method === 'HEAD' ? null : body, {
          headers: {
            'content-type': 'text/yaml; charset=utf-8',
            'cache-control': 'no-store',
            'profile-update-interval': '24',
          },
        });
      }

      if (target === 'v2rayn') {
        const body = buildV2rayN(env);
        return new Response(request.method === 'HEAD' ? null : body, {
          headers: {
            'content-type': 'text/plain; charset=utf-8',
            'cache-control': 'no-cache, no-transform',
            'profile-update-interval': '24',
          },
        });
      }

      // 路由器配置: /<token>?router=1
      const routerMode = url.searchParams.get('router') === '1';
      const config = buildSingbox(env, routerMode);
      return new Response(request.method === 'HEAD' ? null : JSON.stringify(config, null, 2), {
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
          'profile-update-interval': '24',
        },
      });
    } catch (err) {
      return new Response(JSON.stringify({ ok: false, error: String(err?.message || err) }, null, 2), {
        status: 500,
        headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
      });
    }
  },
};
