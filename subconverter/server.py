#!/usr/bin/env python3
# subconverter — 订阅转换服务 v5.1 (Python, 零依赖)
# 从 config.json 读取原始 VLESS/Hysteria2 链接 (至少一个), 按客户端 User-Agent 返回 sing-box / Clash / v2rayN 配置
# 用法: python3 server.py  (监听 127.0.0.1:31001)
#
# v5.1 (2026-08-25) 完全对齐 Cloudflare Worker (abc.js):
#   - 纯硬编码域名, 不再依赖远程 rule_set / rule-provider (规则基础设施已废弃)
#   - HARDCODED_* 数组同步自 abc.js (直连669/代理709/override22)
#   - DNS: dns-proxy=1.1.1.1 DoH 走代理隧道, final=dns-proxy (防污染)
#   - clash: override 规则排最前, 结尾 MATCH,PROXY
#   - fakeip 掩码 198.18.0.0/16, 7890 mixed 入站, 支持 VLESS/HY2 双节点
#
# v5 (2026-08-21) 新增 Hysteria2 (HY2) 支持, 纯加法分支, VLESS-only 行为不变:
#   - config.json 可加可选 rawHy2Url (hysteria2:// 或 hy2://)
#   - HY2 支持端口跳跃: 单端口 / 端口段 a-b / 逗号混合 (sing-box: server_ports+hop_interval; clash: ports+hop-interval)
#   - 有 HY2 时输出双节点 selector (VLESS + HY2 可切换); 没填 HY2 时输出与 v4 逐字节一致
#
# v5.1 (2026-08-21) 支持仅 Hysteria2 (rawVlessUrl 可缺省), 服务名去掉 VLESS 改称"订阅转换服务"
import http.server, json, base64, os, re
from urllib.parse import urlparse, parse_qs, unquote
NL = chr(10)  # newline

CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'config.json')

# ── 规则目录 (单源, 对应 hk /opt/fetch-rules.sh 拉取的 MetaCubeX + DustinWin) ──
# singbox 没有 fallback DNS,因为本来就不支持,多个dns组会增加问题,实测singbox引用去广告会导致路由器侧出问题

DNS = {
    'bootstrap': '180.184.1.1', 'remote': '8.8.8.8',
    'adgServer': 'dns.alidns.com', 'adgPort': 443, 'adgPath': '/dns-query',
}
DASHBOARD_URL = 'https://mirror.notebase.cn/download/yacd-ui.zip'
RULE_SERVER = 'https://mirror.notebase.cn/rules'  # GEOIP 兜底库(自托管, IP→国家映射, 相对稳定)


# ── 手写域名兜底列表 (源自 Shadowrocket 官方规则 + 历史踩坑记录) ──
# 规则集(geosite/geoip)对动态CDN子域名(如 Google Play 分片下载用的
# rr4---sn-xxxx.gvt1.com)覆盖滞后或不全,导致大文件/多并发下载卡死。
# 这里的域名精确匹配放在规则集判断之前,命中即生效,不依赖规则集更新。
# 代理：域名后缀匹配(境外服务/AI/社交等, 同步自 new.worker.js 2026-08-25)
# 代理：域名后缀匹配(境外服务/AI/社交等, 同步自 new.worker.js 2026-08-25)
# 代理：域名后缀匹配(境外服务/AI/社交等, 同步自 new.worker.js 2026-08-25)
# 代理：域名后缀匹配(境外服务/AI/社交等, 同步自 new.worker.js 2026-08-25)
# 代理：域名后缀匹配(境外服务/AI/社交等, 同步自 new.worker.js 2026-08-25)
# 代理：域名后缀匹配(境外服务/AI/社交等, 同步自 new.worker.js 2026-08-25)
HARDCODED_PROXY_SUFFIX = [
    # #Google (102)
    '1e100.net', 'abc.xyz', 'ad-delivery.net', 'admob.com', 'agones.dev', 'ampproject.org',
    'android.com', 'androidify.com', 'angular.dev', 'angular.io', 'angularjs.org', 'apigee.com',
    'appspot.com', 'autodraw.com', 'bazel.build', 'capitalg.com', 'chrome.com', 'chromebook.com',
    'chromecast.com', 'chromeexperiments.com', 'chromestatus.com', 'chromium.org',
    'chronicle.security', 'cloudfunctions.net', 'crashlytics.com', 'creativelab5.com', 'dart.dev',
    'deepmind.com', 'dialogflow.com', 'doubleclick.net', 'dremel.org', 'envoyproxy.io',
    'feedburner.com', 'firebaseapp.com', 'firebaseio.com', 'fitbit.com', 'flutter.dev',
    'forms.gle', 'g.co', 'getmdl.io', 'getoutline.org', 'getpricetag.com', 'gmail.com',
    'gmodules.com', 'go.dev', 'goo.gl', 'goog', 'google-analytics.com', 'google.ca',
    'google.co.in', 'google.co.jp', 'google.co.kr', 'google.co.th', 'google.co.uk', 'google.com',
    'google.com.au', 'google.com.hk', 'google.com.sg', 'google.com.tw', 'google.de', 'google.fr',
    'googleadservices.com', 'googleapis.com', 'googlesyndication.com', 'googletagmanager.com',
    'googleusercontent.com', 'googlezip.net', 'grpc.io', 'gstatic.com', 'gv.com', 'gwtproject.org',
    'istio.io', 'itasoftware.com', 'kaggle.com', 'knative.dev', 'kubernetes.io', 'looker.com',
    'madewithcode.com', 'mandiant.com', 'material.io', 'nest.com', 'orbitera.com',
    'polymer-project.org', 'protobuf.dev', 'recaptcha.net', 'spinnaker.io', 'synergyse.com',
    'tensorflow.org', 'tfhub.dev', 'tiltbrush.com', 'virustotal.com', 'waveprotocol.org',
    'waymo.com', 'waze.com', 'web.app', 'web.dev', 'webmproject.org', 'webrtc.org',
    'whatbrowser.org', 'widevine.com', 'x.company', 'xn--ngstr-lra8j.com',

    # #Googleplay (13)
    'android.clients.google.com', 'app-measurement.com', 'ggpht.com', 'gvt0.com', 'gvt1.com',
    'gvt1.net', 'gvt2.com', 'gvt2.net', 'gvt3.com', 'gvt3.net', 'gvt6.com', 'gvt9.com',
    'play.google.com',

    # #YouTube (4)
    'googlevideo.com', 'youtu.be', 'yt.be', 'ytimg.com',

    # #TikTok (8)
    'ibytedtos.com', 'ibyteimg.com', 'muscdn.com', 'musical.ly', 'tiktok.com', 'tiktokcdn-us.com',
    'tiktokcdn.com', 'tiktokv.com',

    # #Reddit (4)
    'redd.it', 'reddit.com', 'redditmedia.com', 'redditstatic.com',

    # #AI-OpenAI (16)
    'algolia.net', 'chat.openai.com.cdn.cloudflare.net', 'chatgpt.com', 'chatgpt.livekit.cloud',
    'client-api.arkoselabs.com', 'host.livekit.cloud', 'oaistatic.com', 'oaiusercontent.com',
    'openai-api.arkoselabs.com', 'openai.com', 'openaiapi-site.azureedge.net',
    'openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net', 'openaicom.imgix.net',
    'openaicomproductionae4b.blob.core.windows.net', 'production-openaicom-storage.azureedge.net',
    'turn.livekit.cloud',

    # #AI-Claude (12)
    'anthropic-cdn.com', 'anthropic.cloud', 'anthropic.com', 'anthropiccdn.com',
    'anthropicsystem.com', 'clau.de', 'claude.ai', 'claude.com', 'claude.site',
    'claudemcpclient.com', 'claudemcpcontent.com', 'claudeusercontent.com',

    # #AI-Gemini (2)
    'aistudio.google.com', 'gemini.google.com',

    # #AI-其他 (40)
    'character.ai', 'chat.com', 'chatpdf.com', 'civitai.com', 'cohere.ai', 'cohere.com',
    'coze.com', 'cursor.com', 'cursor.sh', 'deepinfra.com', 'elevenlabs.io', 'fireworks.ai',
    'flowgpt.com', 'grok.com', 'groq.com', 'huggingface.co', 'jan.ai', 'leonardo.ai', 'lexica.art',
    'lmarena.ai', 'meta.ai', 'midjourney.com', 'mistral.ai', 'openart.ai', 'openrouter.ai',
    'perplexity.ai', 'poe.com', 'popai.pro', 'pplx.ai', 'prompthero.com', 'replicate.com',
    'runwayml.com', 'sider.ai', 'sora.com', 'stability.ai', 'suno.ai', 'together.ai', 'wombo.ai',
    'x.ai', 'you.com',

    # #Microsoft-Bing (3)
    'bing.com', 'copilot.bing.com', 'onedrive.live.com',

    # #社交 (64)
    'bsky.app', 'bsky.network', 'bsky.social', 'cdninstagram.com', 'clubhouse.com',
    'clubhouse.pubnub.com', 'clubhouseapi.com', 'daum.net', 'discord.com', 'discord.gg',
    'discordapp.com', 'disqus.com', 'fb.com', 'fb.me', 'fbcdn.net', 'fbsbx.com', 'instagr.am',
    'instagram.com', 'joinclubhouse.com', 'kakao.com', 'licdn.com', 'line-apps.com',
    'line-cdn.net', 'line-scdn.net', 'line.me', 'line.naver.jp', 'linkedin.com', 'linktr.ee',
    'mastodon.social', 'messenger.com', 'meta.com', 'mewe.com', 'naver.com', 'ok.ru', 'pinimg.com',
    'pinterest.ca', 'pinterest.com', 'pixnet.net', 'plurk.com', 'quora.com', 'quoracdn.net',
    'signal.me', 'signal.org', 'snapchat.com', 't.co', 't.me', 'tapbots.com', 'tdesktop.com',
    'telegra.ph', 'telegram.me', 'telegram.org', 'telesco.pe', 'threads.com', 'threads.net',
    'tiny.cc', 'tinyurl.com', 'tumblr.com', 'twimg.com', 'twitter.com', 'viber.com',
    'whatsapp.com', 'whatsapp.net', 'whispersystems.org', 'x.com',

    # #社区/论坛 (18)
    '6park.com', '9gag.com', 'ao3.org', 'archiveofourown.org', 'ck101.com', 'dcard.tw',
    'fandom.com', 'goodreads.com', 'hkgolden.com', 'hostloc.com', 'knowyourmeme.com', 'lihkg.com',
    'linux.do', 'metafilter.com', 'mitbbs.com', 'nodeseek.com', 'ptt.cc', 'wattpad.com',

    # #流媒体/二次元 (44)
    'bamgrid.com', 'bandcamp.com', 'boomplay.com', 'buzzsprout.com', 'castbox.fm',
    'crunchyroll.com', 'dailymotion.com', 'deezer.com', 'disneyplus.com', 'dmm.com', 'fast.com',
    'fc2.com', 'genius.com', 'hbo.com', 'hbomax.com', 'hulu.com', 'hulustream.com', 'max.com',
    'mixcloud.com', 'mubi.com', 'netflix.com', 'nflxext.com', 'nflxso.net', 'nflxvideo.net',
    'nicovideo.jp', 'nimg.jp', 'odysee.com', 'overcast.fm', 'pandora.com', 'pixiv.net',
    'podbean.com', 'primevideo.com', 'pv-cdn.net', 'pximg.net', 'rumble.com', 'scdn.co',
    'sndcdn.com', 'soundcloud.com', 'spotify.com', 'tenor.com', 'twitch.tv', 'vevo.com',
    'vimeo.com', 'vimeocdn.com',

    # #维基/百科 (7)
    'wikibooks.org', 'wikidata.org', 'wikimedia.org', 'wikinews.org', 'wikipedia.com',
    'wikipedia.org', 'wikiquote.org',

    # #游戏 (3)
    'battle.net', 'blizzard.com', 'oculus.com',

    # #游戏-国际 (16)
    'ea.com', 'epicgames.com', 'gamer.com.tw', 'gog.com', 'itch.io', 'mahjongsoul.com',
    'minecraft.net', 'nintendo.com', 'paimon.moe', 'pcgamesn.com', 'playstation.com',
    'riotgames.com', 'roblox.com', 'tanks.gg', 'ubi.com', 'wowhead.com',

    # #图床/内容 (8)
    'catbox.moe', 'flickr.com', 'gravatar.com', 'imageshack.us', 'imgur.com', 'openstreetmap.org',
    'raindrop.io', 'staticflickr.com',

    # #开发者/技术 (100)
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

    # #生产力/协作 (12)
    'adobe.com', 'asana.com', 'canva.com', 'evernote.com', 'figma.com', 'grammarly.com',
    'miro.com', 'notion.so', 'slack.com', 'snapseed.com', 'trello.com', 'typora.io',

    # #学习 (18)
    'arxiv.org', 'codecademy.com', 'coursera.org', 'duolingo.com', 'edx.org', 'issuu.com',
    'khanacademy.org', 'kobo.com', 'leetcode.com', 'overleaf.com', 'quizlet.com', 'sci-hub.ru',
    'sci-hub.se', 'scratch.mit.edu', 'scribd.com', 'skillshare.com', 'slideshare.net', 'udemy.com',

    # #旅行/住宿 (9)
    'agoda.com', 'airbnb.com', 'expedia.com', 'hotels.com', 'kayak.com', 'lyft.com',
    'skyscanner.net', 'tripadvisor.com', 'uber.com',

    # #购物/海淘 (15)
    'aliexpress.com', 'amazon.co.jp', 'carousell.com.hk', 'ebay.com', 'etsy.com', 'gumroad.com',
    'mercari.com', 'mercari.jp', 'play-asia.com', 'redbubble.com', 'shein.com', 'shopee.tw',
    'temu.com', 'wish.com', 'yesasia.com',

    # #币圈 (29)
    'binance.com', 'binance.org', 'bitfinex.com', 'bybit.com', 'coinbase.com', 'coingecko.com',
    'coinmarketcap.com', 'crypto.com', 'etherscan.io', 'gate.io', 'huobi.com', 'kraken.com',
    'kucoin.com', 'ledger.com', 'metamask.io', 'mexc.com', 'okex.com', 'okx.com', 'opensea.io',
    'pancakeswap.finance', 'poloniex.com', 'solana.com', 'solscan.io', 'token.im', 'tronscan.org',
    'trustwallet.com', 'uniswap.org', 'upbit.com', 'walletconnect.org',

    # #安卓应用市场 (4)
    'apkmirror.com', 'apkpure.com', 'f-droid.org', 'xda-developers.com',

    # #资讯/新闻 (47)
    'aljazeera.com', 'apnews.com', 'axios.com', 'bbc.co.uk', 'bbc.com', 'bbci.co.uk',
    'bleepingcomputer.com', 'bloomberg.com', 'businessinsider.com', 'cbsnews.com', 'cnn.com',
    'dailymail.co.uk', 'dw.com', 'economist.com', 'engadget.com', 'forbes.com', 'ft.com',
    'ftchinese.com', 'huffpost.com', 'investing.com', 'nbcnews.com', 'newsweek.com',
    'newyorker.com', 'nikkei.com', 'nytimes.com', 'nytimg.com', 'reuters.com', 'reutersmedia.net',
    'rfa.org', 'rfi.fr', 'sciencemag.org', 'scmp.com', 'substack.com', 'swissinfo.ch',
    'theatlantic.com', 'thediplomat.com', 'theguardian.com', 'theintercept.com', 'time.com',
    'tradingview.com', 'v2ex.com', 'voanews.com', 'vox.com', 'washingtonpost.com', 'wsj.com',
    'wsj.net', 'zerohedge.com',

    # #资讯-科技 (8)
    'arstechnica.com', 'gizmodo.com', 'mashable.com', 'techcrunch.com', 'thenextweb.com',
    'theverge.com', 'wired.com', 'ycombinator.com',

    # #安全/VPN (20)
    'browserleaks.com', 'browserleaks.org', 'certificate-transparency.org', 'digicert.com',
    'eurekavpt.com', 'expressvpn.com', 'identrust.com', 'ipleak.net', 'nordvpn.com',
    'observeit.net', 'openvpn.net', 'perfect-privacy.com', 'surfshark.com', 'symauth.com',
    'symcb.com', 'symcd.com', 'teamviewer.com', 'ubnt.com', 'vpnunlimited.com', 'whoer.net',

    # #成人/看片 (76)
    '18comic.org', '91porn.com', '9xbuddy.com', 'avgle.com', 'beeg.com', 'brazzers.com',
    'camwhores.tv', 'chaturbate.com', 'danbooru.donmai.us', 'e-hentai.org', 'e621.net',
    'eporner.com', 'erome.com', 'exhentai.org', 'gelbooru.com', 'hanime.tv', 'hanime1.com',
    'hanimeone.me', 'hitomi.la', 'jable.tv', 'jav.com', 'javbus.com', 'javchu.com', 'javdb.com',
    'javlibrary.com', 'kali.download', 'kat.cr', 'konachan.com', 'livejasmin.com', 'm-team.cc',
    'manyvids.com', 'megaupload.com', 'missav.com', 'missav.ws', 'missav.ai', 'missav.tube',
    'motherless.com', 'myfreecams.com', 'naughtyamerica.com', 'netflav.com', 'nhentai.net',
    'onejav.com', 'onlyfans.com', 'phncdn.com', 'picacomic.com', 'playboy.com', 'pornhd.com',
    'pornhub.com', 'realitykings.com', 'redtube.com', 'rule34.xxx', 'sankakucomplex.com',
    'sehuatang.net', 'sex.com', 'sex8.cc', 'sis001.com', 'south-plus.net', 'spankbang.com',
    'streamate.com', 'stripchat.com', 't66y.com', 'thepiratebay.org', 'tnaflix.com', 'tube8.com',
    'vporn.com', 'wnacg.org', 'x-art.com', 'xhamster.com', 'xnxx.com', 'xtube.com', 'xv-ru.com',
    'xvideos-cdn.com', 'xvideos.com', 'yande.re', 'youjizz.com', 'youporn.com',

    # #其他 (13)
    'archive.org', 'cdn.angruo.com', 'debug.com', 'kenengba.com', 'lithium.com', 'mobile01.com',
    'modmyi.com', 'patreon.com', 'patreonusercontent.com', 'pinboard.in', 'shattered.io',
    'whrq.net', 'zoom.us',
]

# 代理：精确域名匹配
HARDCODED_PROXY_DOMAIN = [
    'api.statsig.com', 'browser-intake-datadoghq.com', 'chat.openai.com.cdn.cloudflare.net',
    'o33249.ingest.sentry.io', 'openai-api.arkoselabs.com',
    'openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net',
    'openaicomproductionae4b.blob.core.windows.net', 'production-openaicom-storage.azureedge.net',
    'static.cloudflareinsights.com', 'copilot.bing.com', 'cdn.angruo.com',
]

# 代理例外：优先于直连父域判断(copilot/Steam商店/OneDrive/境外券商)
HARDCODED_PROXY_OVERRIDE = [
    'copilot.microsoft.com', 'store.steampowered.com', 'api.steampowered.com',
    'steamcommunity.com', 'steamstatic.com', 'onedrive.com', 'futunn.com', 'futu5.com', 'futu.cn',
    'futubull.cn', 'moomoo.com', 'itiger.com', 'tigerbrokers.com', 'tigerbbs.cn', 'longbridge.com',
    'longbridgeapp.com', 'longportapp.com', 'longportapp.cn', 'trade.longportapp.com',
    'openapi.longbridge.cn', 'openapi-quote.longbridge.cn', 'openapi-trade.longbridge.cn',
]

# 代理：域名关键字匹配
HARDCODED_PROXY_KEYWORD = [
    'blogspot', 'facebook', 'gmail', 'google', 'instagram', 'missav', 'openaicom-api', 'pixiv',
    'twitter', 'youtube',
]

# 直连：域名后缀匹配(国内大厂/CDN/境外可直连)
HARDCODED_DIRECT_SUFFIX = [
    # #Apple (12)
    'aaplimg.com', 'apple-cloudkit.com', 'apple-dns.net', 'apple.co', 'apple.com', 'apple.news',
    'appstore.com', 'cdn-apple.com', 'icloud-content.com', 'icloud.com', 'me.com', 'mzstatic.com',

    # #Microsoft (14)
    'microsoft.com', 'microsoftonline.com', 'msecnd.net', 'msftconnecttest.com', 'msftncsi.com',
    'office.com', 'office365.com', 'outlook.com', 's-microsoft.com', 'sharepoint.com',
    'visualstudio.com', 'windows.com', 'windowsupdate.com', 'xbox.com',

    # #腾讯系 (25)
    'dns.pub', 'dnspod.com', 'doh.pub', 'gcloudcs.com', 'gtimg.com', 'idqqimg.com', 'myapp.com',
    'myqcloud.com', 'qcloud.com', 'qidian.com', 'qq.com', 'servicewechat.com', 'tencent-cloud.com',
    'tencent-cloud.net', 'tencent.com', 'tencentcloud.com', 'tencentmusic.com', 'tenpay.com',
    'wechat.com', 'weishi.com', 'weixin.com', 'weixinbridge.com', 'weiyun.com', 'wxlivecdn.com',
    'wxwork.com',

    # #阿里系 (35)
    '1688.com', 'alibaba-inc.com', 'alibaba.com', 'alicdn.com', 'alidns.com', 'alikunlun.com',
    'alipan.com', 'alipay.com', 'aliyun.com', 'aliyuncs.com', 'aliyundrive.com', 'amap.com',
    'antfin.com', 'antgroup.com', 'autonavi.com', 'cainiao.com', 'dingtalk.com', 'ele.me',
    'elemecdn.com', 'etao.com', 'fliggy.com', 'freshippo.com', 'mxhichina.com', 'taobao.com',
    'taopiaopiao.com', 'teambition.com', 'tmall.com', 'tmall.hk', 'wandoujia.com', 'xiami.com',
    'xiami.net', 'ykimg.com', 'youku.com', 'yunos.com', 'yuque.com',

    # #字节系 (50)
    'animebytes.tv', 'byte008.com', 'bytedance.com', 'bytedns.net', 'byteimg.com', 'bytelb.net',
    'dongchedi.com', 'douyin.com', 'douyinact.com', 'douyinact.net', 'douyincdn.com',
    'douyinclips.com', 'douyincloud.net', 'douyincloud.run', 'douyinec.com', 'douyinhanyu.com',
    'douyinliving.com', 'douyinmusicclips.com', 'douyinmusicpromotion.com', 'douyinmusicvideo.com',
    'douyinpay.com', 'douyinpic.com', 'douyinshortvideo.com', 'douyinstatic.com',
    'douyinvideo.net', 'douyinvod.com', 'fanqienovel.com', 'feiliao.com', 'feishu.cn',
    'feishu.com', 'huoshan.com', 'huoshanlive.com', 'idouyinliving.com', 'idouyinpic.com',
    'idouyinstatic.com', 'idouyinvod.com', 'iesdouyin.com', 'iesdouyin.net', 'ihuoshanlive.com',
    'ixigua.com', 'kaiyanapp.com', 'larkoffice.com', 'larksuite.com', 'pstatp.com', 'snssdk.com',
    'toutiao.com', 'toutiaoapi.com', 'volcengine.com', 'volces.com', 'zijieapi.com',

    # #百度系 (11)
    'baidu.com', 'baidubcr.com', 'baidupcs.com', 'bcebos.com', 'bdatu.com', 'bdimg.com',
    'bdstatic.com', 'bdurl.net', 'duxiaoman.com', 'hao123.com', 'yunjiasu-cdn.net',

    # #京东系 (7)
    '360buy.com', '360buyimg.com', 'jcloud.com', 'jd.com', 'jd.hk', 'jdpay.com', 'jdwl.com',

    # #拼多多系 (3)
    'pddpic.com', 'pinduoduo.com', 'yangkeduo.com',

    # #美团系 (9)
    'dianping.com', 'maoyan.com', 'meituan.com', 'meituan.net', 'meitudata.com', 'meitustat.com',
    'meixincdn.com', 'mobike.com', 'sankuai.com',

    # #美图 (2)
    'meipai.com', 'meitu.com',

    # #小米系 (8)
    'mi-img.com', 'mi.com', 'mipay.com', 'miui.com', 'miwifi.com', 'redmi.com', 'xiaomi.com',
    'xiaomi.net',

    # #网易系 (11)
    '126.com', '126.net', '127.net', '163.com', '163yun.com', 'duokan.com', 'kaola.com',
    'lofter.com', 'netease.com', 'ydstatic.com', 'youdao.com',

    # #快手系 (5)
    'gifshow.com', 'kuaishou.com', 'kuaishou.tv', 'kwimgs.com', 'yximgs.com',

    # #哔哩哔哩 (7)
    'acgvideo.com', 'biliapi.com', 'biliapi.net', 'bilibili.com', 'bilibili.tv', 'bilivideo.com',
    'hdslb.com',

    # #爱奇艺 (3)
    'iqiyi.com', 'iqiyipic.com', 'qiyi.com',

    # #视频平台 (11)
    'aixifan.com', 'baofeng.com', 'fun.tv', 'hitv.com', 'le.com', 'letv.com', 'maoyun.tv',
    'mgtv.com', 'miaopai.com', 'pptv.com', 'v-56.com',

    # #直播 (6)
    'chushou.tv', 'douyu.com', 'huajiao.com', 'huanju.com', 'huya.com', 'yy.com',

    # #新闻媒体 (16)
    'cailianpress.com', 'cctv.com', 'cctvpic.com', 'china.com', 'chinanews.com', 'huanqiu.com',
    'huxiucdn.com', 'ifeng.com', 'jiemian.com', 'livechina.com', 'myzaker.com', 'qdaily.com',
    'takungpao.com', 'xinhuanet.com', 'yidianzixun.com', 'zhongguowangshi.com',

    # #科技媒体 (5)
    '36kr.com', 'cnbeta.com', 'huxiu.com', 'ifanr.com', 'pingwest.com',

    # #知乎 (2)
    'zhihu.com', 'zhimg.com',

    # #小红书 (2)
    'xhscdn.com', 'xiaohongshu.com',

    # #豆瓣 (2)
    'douban.com', 'doubanio.com',

    # #社交-国内 (5)
    'immomo.com', 'kaixin001.com', 'renren.com', 'tantanapp.com', 'xiaonei.com',

    # #新浪微博 (4)
    'sina.com', 'weibo.com', 'weibocdn.com', 'weico.cc',

    # #搜狐搜狗 (7)
    'sogo.com', 'sogou.com', 'sogoucdn.com', 'sohu-inc.com', 'sohu.com', 'sohucs.com', 'soku.com',

    # #360 (6)
    '360.com', '360in.com', 'qhimg.com', 'qhres.com', 'qihoo.com', 'so.com',

    # #滴滴系 (4)
    'didi.com', 'didialift.com', 'didiglobal.com', 'udache.com',

    # #携程/OTA (9)
    'ctrip.com', 'elong.com', 'ly.com', 'qunar.com', 'qyer.com', 'qyerstatic.com', 'tongcheng.com',
    'trip.com', 'tuniu.com',

    # #交通/出行 (9)
    '12306.com', 'ceair.com', 'csair.com', 'hellobike.com', 'hnair.com', 'ishansong.com',
    'qingju.com', 'umetrip.com', 'zuche.com',

    # #苏宁 (1)
    'suning.com',

    # #OPPO/一加/realme (4)
    'heytapmobi.com', 'oneplus.com', 'oppo.com', 'realme.com',

    # #华为荣耀 (5)
    'hicloud.com', 'honor.com', 'huawei.com', 'huaweicloud.com', 'vmall.com',

    # #联想 (2)
    'lenovo.com', 'thinkpad.com',

    # #手机/数码 (6)
    'coolpad.com', 'gfan.com', 'nubia.com', 'samsung.com', 'smartisan.com', 'vivo.com',

    # #魅族 (1)
    'meizu.com',

    # #运营商 (6)
    '10010.com', 'chinamobile.com', 'chinanetcenter.com', 'chinaunicom.com', 'cmpassport.com',
    'cmpay.com',

    # #银行/金融 (29)
    '800best.com', '95516.com', 'abchina.com', 'bankcomm.com', 'ccb.com', 'cebbank.com',
    'citicbank.com', 'cmbchina.com', 'cmbimg.com', 'dfcfw.com', 'eastmoney.com', 'feidee.com',
    'hexun.com', 'jimubox.com', 'lakala.com', 'lu.com', 'lufax.com', 'pingan.com', 'psbc.com',
    'renrendai.com', 'ronghub.com', 'tianyancha.com', 'unionpay.com', 'wacai.com', 'webank.com',
    'xin.com', 'xueqiu.com', 'yeepay.com', 'zhongan.com',

    # #财经媒体 (4)
    'caixin.com', 'jin10.com', 'wallstreetcn.com', 'yicai.com',

    # #房产/居住 (10)
    '5i5j.com', 'anjuke.com', 'beike.com', 'fang.com', 'ke.com', 'leju.com', 'lianjia.com',
    'soufun.com', 'xiangdao.com', 'ziroom.com',

    # #招聘 (8)
    '51job.com', 'careerintlinc.com', 'chinahr.com', 'job51.com', 'lagou.com', 'liepin.com',
    'zhaopin.com', 'zhipin.com',

    # #电商/零售 (15)
    'dangdang.com', 'dewu.com', 'dingdong.com', 'dmall.com', 'jddj.com', 'manmanbuy.com',
    'missfresh.com', 'mogujie.com', 'secoo.com', 'smzdm.com', 'vip.com', 'weidian.com',
    'xiachufang.com', 'yanxuan.com', 'yonghui.com',

    # #闲鱼/二手 (2)
    'goofish.com', 'zhuanzhuan.com',

    # #分类信息 (3)
    '58.com', '58ganji.com', 'ganji.com',

    # #物流/快递 (7)
    'deppon.com', 'jtexpress.com', 'kuaidi100.com', 'sf-express.com', 'yunda56.com', 'yundaex.com',
    'zto.com',

    # #教育 (4)
    'hujiang.com', 'xueersi.com', 'yuanfudao.com', 'zuoyebang.com',

    # #医疗 (5)
    'chunyu.mobi', 'chunyuyisheng.com', 'dxycdn.com', 'guahao.com', 'haodf.com',

    # #AI-国内 (3)
    'deepseek.com', 'iflytek.com', 'xunfei.com',

    # #游戏/体育 (9)
    '4399.com', 'dongqiudi.com', 'hupu.com', 'igamecj.com', 'mihoyo.com', 'miyoushe.com',
    'taptap.com', 'wanmei.com', 'zhibo8.cc',

    # #游戏资讯 (4)
    '3dmgame.com', 'ali213.net', 'gamersky.com', 'ngabbs.com',

    # #数字阅读 (6)
    'hongxiu.com', 'jjwxc.net', 'qimao.com', 's-reader.com', 'yuewen.com', 'zongheng.com',

    # #内容/博客 (11)
    'fandeng.com', 'igetget.com', 'izuiyou.com', 'jianshu.com', 'kkmh.com', 'kuaikanmanhua.com',
    'luojilab.com', 'raychase.net', 'scomper.me', 'sspai.com', 'zhangzishi.cc',

    # #影视资源 (9)
    'dytt8.net', 'ourdvs.com', 'xinpianchang.com', 'zimuzu.io', 'zimuzu.tv', 'zmz2019.com',
    'zmzapi.com', 'zmzapi.net', 'zmzfile.com',

    # #音频 (6)
    'kugou.com', 'kugou.net', 'lizhi.fm', 'qingting.fm', 'ximalaya.com', 'xmcdn.com',

    # #云/CDN (18)
    '21vianet.com', 'akadns.net', 'ccgslb.com', 'ccgslb.net', 'cdngslb.com', 'chinacache.com',
    'fclouddns.net', 'geilicdn.com', 'ip-cdn.com', 'ks-cdn.com', 'ksyun.com', 'ksyuncdn.com',
    'qingcloud.com', 'qiniu.com', 'staticdn.net', 'upyun.com', 'wangsu.com', 'xinnet.com',

    # #开发者-国内 (9)
    'coding.net', 'csdn.net', 'docschina.org', 'gitcode.com', 'gitee.com', 'nim-lang-cn.org',
    'oschina.net', 'seafile.com', 'segmentfault.com',

    # #学术-国内 (2)
    'cnki.net', 'cqvip.com',

    # #词典/笔记 (11)
    'eudic.net', 'frdic.com', 'godic.net', 'iciba.com', 'jidian.im', 'lanhuapp.com', 'mubu.com',
    'processon.com', 'shimo.im', 'wps.com', 'yinxiang.com',

    # #工具 (13)
    'air-matters.com', 'air-matters.io', 'b612.net', 'infinitynewtab.com', 'ip.la', 'ipip.net',
    'loli.net', 'moji.com', 'sm.ms', 'snapdrop.net', 'todesk.com', 'wondershare.com', 'xunlei.com',

    # #应用商店 (2)
    'anzhi.com', 'coolapk.com',

    # #汽车/制造 (23)
    'bitauto.com', 'byd.com', 'changhe.com', 'changhong.com', 'che168.com', 'chery.com', 'dji.com',
    'geely.com', 'gree.com', 'guazi.com', 'haier.com', 'hisense.com', 'inspur.com', 'konka.com',
    'lixiang.com', 'midea.com', 'nio.com', 'renrenche.com', 'skyworth.com', 'taoche.com',
    'tcl.com', 'xiaopeng.com', 'yiche.com',

    # #PT/影音社区 (27)
    'awesome-hd.me', 'beitaichufang.com', 'broadcasthe.net', 'chdbits.co',
    'classix-unlimited.co.uk', 'empornium.me', 'gazellegames.net', 'hdbits.org', 'hdchina.org',
    'hdhome.org', 'hdsky.me', 'icetorrent.org', 'jpopsuki.eu', 'morethan.tv', 'myanonamouse.net',
    'nanyangpt.com', 'ncore.cc', 'open.cd', 'ourbits.club', 'passthepopcorn.me', 'privatehd.to',
    'pterclub.com', 'redacted.ch', 'springsunday.net', 'tjupt.org', 'totheglory.im', 'zhuihd.com',

    # #境外可直连-学术 (53)
    'acs.org', 'aip.org', 'ams.org', 'annualreviews.org', 'aps.org', 'ascelibrary.org', 'asm.org',
    'asme.org', 'astm.org', 'bmj.com', 'cambridge.org', 'cas.org', 'clarivate.com',
    'ebscohost.com', 'emerald.com', 'engineeringvillage.com', 'icevirtuallibrary.com', 'ieee.org',
    'imf.org', 'iop.org', 'jamanetwork.com', 'jhu.edu', 'jstor.org', 'karger.com', 'libguides.com',
    'mpg.de', 'myilibrary.com', 'nature.com', 'oecd-ilibrary.org', 'osapublishing.org', 'oup.com',
    'ovid.com', 'oxfordartonline.com', 'oxfordbibliographies.com', 'oxfordmusiconline.com',
    'pnas.org', 'proquest.com', 'rsc.org', 'sagepub.com', 'sciencedirect.com', 'scopus.com',
    'siam.org', 'spiedigitallibrary.org', 'springer.com', 'springerlink.com', 'tandfonline.com',
    'un.org', 'uni-bielefeld.de', 'webofknowledge.com', 'westlaw.com', 'wiley.com',
    'worldbank.org', 'worldscientific.com',

    # #境外可直连-其他 (30)
    'accuweather.com', 'acm.org', 'amd.com', 'booking.com', 'bstatic.com', 'gandi.net',
    'ipv6-test.com', 'java.com', 'kaspersky-labs.com', 'netspeedtestmaster.com',
    'network-test.debian.org', 'ntp.org', 'nvidia.com', 'oracle.com', 'paypal.com',
    'paypalobjects.com', 'qualcomm.com', 'redhat.com', 'steam-chat.com', 'steamcdn-a.akamaihd.net',
    'steamcontent.com', 'steamgames.com', 'steampowered.com', 'steamstat.us',
    'steamusercontent.com', 'test-ipv6.com', 'udacity.com', 'vmware.com', 'weather.com',
    'whatismyip.com',

    # #特殊/本地 (3)
    'cn', 'lan', 'local',

    # #自有域名 (1)
    'uuuio.com',

    # #其他 (47)
    '21cn.com', '2345.com', '343480.com', '51ym.me', '71.am.com', '8686c.com', 'aicoinstorge.com',
    'allawntech.com', 'baduziyuan.com', 'biyao.com', 'bjango.com', 'camera360.com', 'ch.com',
    'chinaso.com', 'chua.pro', 'chuimg.com', 'com-hs-hkdy.com', 'czybjz.com', 'dandanzan.com',
    'feng.com', 'fengkongcloud.com', 'fjhps.com', 'h3c.com', 'haidilao.com', 'hikvision.com',
    'hostbuf.com', 'i.cloud.com', 'ithome.com', 'jstucdn.com', 'keepcdn.com', 'keepfrds.com',
    'ksosoft.com', 'kuyunbo.club', 'liangxin.com', 'luckincoffee.com', 'madsrevolution.net',
    'mixue.com', 'moke.com', 'ruguoapp.com', 'sandai.net', 'snwx.com', 'tfogc.com', 'uning.com',
    'wnl.com', 'yonyou.com', 'zhongke.com', 'zhubajie.com',
]

# 直连：精确域名匹配
HARDCODED_DIRECT_DOMAIN = [
    'blzddist1-a.akamaihd.net', 'download.jetbrains.com', 'file-igamecj.akamaized.net',
    'images-cn.ssl-images-amazon.com', 'officecdn-microsoft-com.akamaized.net',
    'speedtest.macpaw.com', 'www-cdn.icloud.com.akadns.net',
]

# 代理：IP段匹配(Google/Telegram/Anthropic)
HARDCODED_PROXY_IP_CIDR = [
    # #Google (13)
    '108.177.0.0/17', '142.250.0.0/15', '172.217.0.0/16', '173.194.0.0/16', '209.85.128.0/17',
    '216.239.32.0/19', '216.58.0.0/17', '216.58.192.0/19', '64.233.160.0/19', '66.102.0.0/20',
    '66.249.64.0/19', '72.14.192.0/18', '74.125.0.0/16',

    # #Google (12)
    '34.0.0.0/15', '34.2.0.0/16', '34.3.0.0/16', '34.4.0.0/16', '34.64.0.0/10', '35.184.0.0/13',
    '35.192.0.0/12', '35.208.0.0/12', '35.224.0.0/12', '35.240.0.0/13', '8.34.208.0/20',
    '8.35.192.0/19',

    # #Google (2)
    '8.8.4.0/24', '8.8.8.0/24',

    # #Telegram (7)
    '109.239.140.0/24', '149.154.160.0/20', '91.108.12.0/22', '91.108.16.0/22', '91.108.4.0/22',
    '91.108.56.0/22', '91.108.8.0/22',

    # #Anthropic-Claude (1)
    '160.79.104.0/21',
]














# ── 缓存 ──
_cache = {'mtime': 0, 'singbox': None, 'singbox_router': None, 'clash': None, 'raw_vless': None, 'node_name': '🇯🇵 Osaka'}


def parse_vless(raw_url):
    u = urlparse(raw_url)
    qs = parse_qs(u.query)
    return {
        'address': u.hostname, 'port': u.port or 443,
        'uuid': u.username, 'flow': qs.get('flow', ['xtls-rprx-vision'])[0],
        'sni': qs.get('sni', [''])[0], 'pbk': qs.get('pbk', [''])[0],
        'sid': qs.get('sid', [''])[0], 'spx': qs.get('spx', [''])[0],
        'encryption': qs.get('encryption', ['none'])[0],
    }


def parse_hysteria2(raw, fallback_name='🇭🇰 Hysteria2'):
    """解析 hysteria2:// 或 hy2:// 链接。支持端口跳跃: 单端口 / 端口段 a-b / 逗号混合。

    返回 dict: {type, name, address, port, server_ports, hop_interval,
                password, obfs, obfs_password, sni, insecure, alpn}
    server_ports 为 None (单端口) 或 ['20000:30000', '40000', ...] 形态 (端口段转冒号)。
    """
    if raw.startswith('hy2://'):
        scheme_len = 6
    elif raw.startswith('hysteria2://'):
        scheme_len = 12
    else:
        raise ValueError('无效 Hysteria2 URL (必须以 hysteria2:// 或 hy2:// 开头)')

    without_scheme = raw[scheme_len:]
    hash_idx = without_scheme.find('#')
    without_hash = without_scheme[:hash_idx] if hash_idx >= 0 else without_scheme
    hash_part = without_scheme[hash_idx + 1:] if hash_idx >= 0 else ''
    q_idx = without_hash.find('?')
    before_query = without_hash[:q_idx] if q_idx >= 0 else without_hash
    query = without_hash[q_idx + 1:] if q_idx >= 0 else ''
    qs = parse_qs(query)

    at = before_query.rfind('@')
    if at <= 0:
        raise ValueError('Hysteria2 URL 缺少 password@host')
    password = before_query[:at]
    host_port = before_query[at + 1:]

    # host[:portpart] 解析 (支持 IPv6 [::1])
    hp = host_port.rstrip('/')
    if hp.startswith('['):
        end = hp.find(']')
        if end == -1:
            raise ValueError('IPv6 地址缺少 ]')
        server = hp[1:end]
        port_part = hp[end + 1:].lstrip(':') or '443'
    else:
        colon = hp.rfind(':')
        if colon == -1:
            server, port_part = hp, '443'
        else:
            server, port_part = hp[:colon], hp[colon + 1:] or '443'

    # 端口列表/段 → server_ports (['20000:30000', '40000'])
    tokens = [t for t in port_part.split(',') if t]
    if not tokens:
        raise ValueError('Hysteria2 URL 缺少端口')
    first_port = None
    server_ports = None
    norm = []
    has_range_or_multi = False
    for token in tokens:
        m = re.match(r'^(\d+)(?:-(\d+))?$', token)
        if not m:
            raise ValueError(f'无效端口/端口段: {token}')
        a, b = int(m.group(1)), int(m.group(2)) if m.group(2) else None
        b = b if b is not None else a
        if not (1 <= a <= 65535 and 1 <= b <= 65535 and b >= a):
            raise ValueError(f'无效端口/端口段: {token}')
        if first_port is None:
            first_port = a
        if m.group(2):
            has_range_or_multi = True
            norm.append(f'{a}:{b}')
        else:
            if len(tokens) > 1:
                has_range_or_multi = True
            norm.append(str(a))
    if has_range_or_multi:
        server_ports = norm

    name = unquote(hash_part) if hash_part else fallback_name
    obfs_type = qs.get('obfs', [''])[0]
    alpn_raw = qs.get('alpn', ['h3'])[0]
    alpn = [s.strip() for s in alpn_raw.split(',') if s.strip()]

    return {
        'type': 'hysteria2',
        'name': name,
        'address': server,
        'port': first_port,
        'server_ports': server_ports,
        'hop_interval': qs.get('hop-interval', ['300s'])[0],
        'password': password,
        'obfs': obfs_type,
        'obfs_password': qs.get('obfs-password', [''])[0],
        'sni': qs.get('sni', [''])[0] or server,
        'insecure': qs.get('insecure', [''])[0] == '1',
        'alpn': alpn,
    }


def _literal_ip_cidr(address):
    """节点地址若是字面 IP → CIDR 段 (IPv4 /32, IPv6 /128), 域名返回 None"""
    a = str(address or '').strip()
    if re.match(r'^\d{1,3}(?:\.\d{1,3}){3}$', a):
        return f'{a}/32'
    if ':' in a:
        return f'[{a}]/128'
    return None


# singbox 不生成 ads 规则集(广告拦截由自建 DoH/AGH 处理, 且 singbox 规则未引用)

def _vless_outbound(node):
    """VLESS 出站 (键序与 v4 完全一致, 保证 VLESS-only 逐字节不变)"""
    return {
        'type': 'vless',
        'tag': node['name'],
        'server': node['address'],
        'server_port': int(node['port']),
        'uuid': node['uuid'],
        'flow': node['flow'],
        'tls': {
            'enabled': True,
            'server_name': node['sni'],
            'utls': {'enabled': True, 'fingerprint': 'chrome'},
            'reality': {'enabled': True, 'public_key': node['pbk'], 'short_id': node['sid']},
        },
    }


def _hy2_outbound(node):
    """Hysteria2 出站 (支持端口跳跃: server_ports + hop_interval)"""
    ob = {
        'type': 'hysteria2',
        'tag': node['name'],
        'server': node['address'],
        'server_port': node['port'],
    }
    if node.get('server_ports'):
        ob['server_ports'] = node['server_ports']
        ob['hop_interval'] = node.get('hop_interval') or '300s'
    ob['password'] = node['password']
    if node.get('obfs'):
        ob['obfs'] = {'type': node['obfs'], 'password': node.get('obfs_password') or ''}
    tls = {'enabled': True, 'server_name': node.get('sni') or node['address']}
    if node.get('insecure'):
        tls['insecure'] = True
    if node.get('alpn'):
        tls['alpn'] = node['alpn']
    ob['tls'] = tls
    return ob


def build_singbox(nodes, router_mode=False):
    proxy_tag = 'proxy'
    node_hosts = [n['address'] for n in nodes]

    dns_rules = [
        {'clash_mode': 'direct', 'action': 'route', 'server': 'dns-direct'},
        {'clash_mode': 'global', 'action': 'route', 'server': 'dns-proxy'},
        {'domain': node_hosts, 'server': 'dns-bootstrap'},
        {'domain_suffix': HARDCODED_PROXY_OVERRIDE, 'query_type': ['A', 'AAAA'], 'server': 'dns-fakeip'},
        {'domain_suffix': HARDCODED_PROXY_OVERRIDE, 'server': 'dns-proxy'},
        {'domain_suffix': HARDCODED_DIRECT_SUFFIX, 'server': 'dns-direct'},
        {'domain': HARDCODED_DIRECT_DOMAIN, 'server': 'dns-direct'},
        {'domain_suffix': HARDCODED_PROXY_SUFFIX, 'query_type': ['A', 'AAAA'], 'server': 'dns-fakeip'},
        {'domain_suffix': HARDCODED_PROXY_SUFFIX, 'server': 'dns-proxy'},
        {'domain': HARDCODED_PROXY_DOMAIN, 'query_type': ['A', 'AAAA'], 'server': 'dns-fakeip'},
        {'domain': HARDCODED_PROXY_DOMAIN, 'server': 'dns-proxy'},
        {'domain_keyword': HARDCODED_PROXY_KEYWORD, 'query_type': ['A', 'AAAA'], 'server': 'dns-fakeip'},
        {'domain_keyword': HARDCODED_PROXY_KEYWORD, 'server': 'dns-proxy'},
        # geosite-cn 国内域名大全: 未硬编码的国内域名(字节新CDN等) DNS 走阿里, 出口国内 + geoDNS 正确
        {'rule_set': ['geosite-cn'], 'server': 'dns-direct'},
    ]

    route_rules = [
        {'action': 'sniff'},
        {'clash_mode': 'direct', 'outbound': 'direct'},
        {'clash_mode': 'global', 'outbound': proxy_tag},
        {'protocol': 'dns', 'action': 'hijack-dns'},
        {'domain': node_hosts, 'outbound': 'direct'},
        {'domain_suffix': HARDCODED_PROXY_OVERRIDE, 'outbound': proxy_tag},
        {'domain_suffix': HARDCODED_DIRECT_SUFFIX, 'outbound': 'direct'},
        {'domain': HARDCODED_DIRECT_DOMAIN, 'outbound': 'direct'},
        {'ip_cidr': HARDCODED_PROXY_IP_CIDR, 'outbound': proxy_tag},
        {'domain_suffix': HARDCODED_PROXY_SUFFIX, 'outbound': proxy_tag},
        {'domain': HARDCODED_PROXY_DOMAIN, 'outbound': proxy_tag},
        {'domain_keyword': HARDCODED_PROXY_KEYWORD, 'outbound': proxy_tag},
        {'ip_is_private': True, 'outbound': 'direct'},
        # geosite-cn 域名级国内兜底: 与 GEOIP 兜底互补(域名先判), 国内域名直接出站
        {'rule_set': ['geosite-cn'], 'outbound': 'direct'},
        # GEOIP 兜底层: 硬编码规则没列到的域名按解析出的IP归属判断, 中国IP直接出站
        {'rule_set': ['geoip-cn'], 'outbound': 'direct'},
    ]

    outbounds = []
    for n in nodes:
        outbounds.append(_vless_outbound(n) if n.get('type') != 'hysteria2' else _hy2_outbound(n))
    node_tags = [o['tag'] for o in outbounds]
    outbounds.append({'type': 'selector', 'tag': proxy_tag, 'outbounds': node_tags, 'default': node_tags[0]})
    outbounds.append({'type': 'selector', 'tag': 'global', 'outbounds': ['proxy', 'direct', 'block'], 'default': 'proxy'})
    outbounds.append({'type': 'direct', 'tag': 'direct'})
    outbounds.append({'type': 'block', 'tag': 'block'})

    tun = {'type': 'tun', 'tag': 'tun-in', 'interface_name': 'singbox',
           'address': ['172.19.0.1/30'], 'mtu': 9000, 'auto_route': True,
           'strict_route': True, 'stack': 'system' if router_mode else 'gvisor'}
    if router_mode:
        tun['auto_redirect'] = True

    return {
        'log': {'level': 'warn', 'timestamp': True},
        'dns': {
            'servers': [
                {'tag': 'dns-bootstrap', 'type': 'udp', 'server': DNS['bootstrap']},
                {'tag': 'dns-direct', 'type': 'https', 'server': DNS['adgServer'], 'server_port': DNS['adgPort'],
                 'path': DNS['adgPath'], 'domain_resolver': 'dns-bootstrap'},
                # dns-proxy 用 DoH(1.1.1.1) 走隧道: TCP传输VLESS也稳 + 加密 + 防污染(与 abc.js 对齐)
                {'tag': 'dns-proxy', 'type': 'https', 'server': '1.1.1.1', 'server_port': 443,
                 'path': '/dns-query', 'detour': proxy_tag},
                {'tag': 'dns-fakeip', 'type': 'fakeip', 'inet4_range': '198.18.0.0/16'},
            ],
            'rules': dns_rules,
            'final': 'dns-proxy',
        },
        'inbounds': [
            tun,
            {'type': 'mixed', 'tag': 'mixed-in', 'listen': '0.0.0.0', 'listen_port': 7890},
        ],
        'outbounds': outbounds,
        'route': {
            'default_domain_resolver': 'dns-bootstrap',
            'auto_detect_interface': True,
            'rules': route_rules,
            'rule_set': [{
                'type': 'remote', 'tag': 'geosite-cn', 'format': 'binary',
                'url': RULE_SERVER + '/sing/geosite/cn.srs',
                'download_detour': 'direct', 'update_interval': '24h',
            }, {
                'type': 'remote', 'tag': 'geoip-cn', 'format': 'binary',
                'url': RULE_SERVER + '/sing/geoip/cn.srs',
                'download_detour': 'direct', 'update_interval': '24h',
            }],
            'final': proxy_tag,
        },
        'experimental': {
            'cache_file': {'enabled': True, 'store_fakeip': True},
            'clash_api': {
                'external_controller': '0.0.0.0:9090',
                'external_ui': 'ui',
                'external_ui_download_url': DASHBOARD_URL,
                'external_ui_download_detour': 'direct',
                'default_mode': 'rule',
                'access_control_allow_private_network': True,
            },
        },
    }


def _clash_vless_lines(node, q):
    """VLESS clash proxy 块 (与 v4 逐字节一致)"""
    return [
        f'  - name: {q(node["name"])}',
        '    type: vless',
        f'    server: {q(node["address"])}',
        f'    port: {node["port"]}',
        f'    uuid: {q(node["uuid"])}',
        '    udp: true',
        '    network: tcp',
        f'    flow: {q(node["flow"])}',
        '    tls: true',
        f'    servername: {q(node["sni"])}',
        '    client-fingerprint: chrome',
        '    reality-opts:',
        f'      public-key: {q(node["pbk"])}',
        f'      short-id: {q(node["sid"])}',
    ]


def _clash_hy2_lines(node, q):
    """Hysteria2 clash proxy 块 (支持端口跳跃: ports + hop-interval)"""
    lines = [
        f'  - name: {q(node["name"])}',
        '    type: hysteria2',
        f'    server: {q(node["address"])}',
    ]
    if node.get('server_ports'):
        ports_str = ','.join(p.replace(':', '-') for p in node['server_ports'])
        lines.append(f'    ports: {q(ports_str)}')
        lines.append('    hop-interval: 300')
    else:
        lines.append(f'    port: {node["port"]}')
    lines.append(f'    password: {q(node["password"])}')
    if node.get('obfs'):
        lines.append(f'    obfs: {q(node["obfs"])}')
        lines.append(f'    obfs-password: {q(node.get("obfs_password") or "")}')
    lines.append(f'    sni: {q(node.get("sni") or node["address"])}')
    if node.get('insecure'):
        lines.append('    skip-cert-verify: true')
    if node.get('alpn'):
        lines.append(f'    alpn: {json.dumps(node["alpn"])}')
    lines.append('    udp: true')
    return lines


def build_clash(nodes):
    q = lambda s: json.dumps(str(s), ensure_ascii=False)

    proxy = []
    for n in nodes:
        if n.get('type') == 'hysteria2':
            proxy += _clash_hy2_lines(n, q)
        else:
            proxy += _clash_vless_lines(n, q)
    node_names = [n['name'] for n in nodes]

    # 与 abc.js buildClash 对齐: override 排最前(否则 store.steampowered.com 被 steampowered.com 直连吞), 纯硬编码无 rule-providers
    rules = []
    for d in HARDCODED_PROXY_OVERRIDE:
        rules.append(f'DOMAIN-SUFFIX,{d},PROXY')
    for d in HARDCODED_DIRECT_SUFFIX:
        rules.append(f'DOMAIN-SUFFIX,{d},DIRECT')
    for d in HARDCODED_DIRECT_DOMAIN:
        rules.append(f'DOMAIN,{d},DIRECT')
    for d in HARDCODED_PROXY_SUFFIX:
        rules.append(f'DOMAIN-SUFFIX,{d},PROXY')
    for d in HARDCODED_PROXY_DOMAIN:
        rules.append(f'DOMAIN,{d},PROXY')
    for d in HARDCODED_PROXY_KEYWORD:
        rules.append(f'DOMAIN-KEYWORD,{d},PROXY')
    for d in HARDCODED_PROXY_IP_CIDR:
        rules.append(f'IP-CIDR,{d},PROXY,no-resolve')
    rules.append('GEOIP,CN,DIRECT')  # GEOIP 兜底: 解析出中国IP即直连
    rules.append('MATCH,PROXY')

    lines = [
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
        f'    - {DNS["bootstrap"]}',
        '  nameserver:',
        '    - "https://dns.alidns.com/dns-query"',
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
    ]
    lines.extend(proxy)
    lines += [
        'proxy-groups:',
        '  - name: PROXY',
        '    type: select',
        f'    proxies: [{", ".join(q(x) for x in node_names)}]',
        '  - name: GLOBAL',
        '    type: select',
        '    proxies: ["PROXY", "DIRECT", "REJECT"]',
        'rules:',
    ]
    for r in rules:
        lines.append(f'  - {q(r)}')
    return NL.join(lines) + NL


def get_configs():
    try:
        mtime = os.path.getmtime(CONFIG_PATH)
    except OSError:
        mtime = 0
    if mtime != _cache['mtime']:
        with open(CONFIG_PATH) as f:
            raw = json.load(f)
        raw_vless = raw.get('rawVlessUrl', '').strip()
        raw_hy2 = raw.get('rawHy2Url', '').strip()
        name = raw.get('nodeName', '🇯🇵 Osaka')
        nodes = []
        if raw_vless:
            if not raw_vless.startswith('vless://'):
                raise ValueError('config.json 的 rawVlessUrl 不是 vless:// 开头')
            v = parse_vless(raw_vless)
            v['name'] = name
            nodes.append(v)
        if raw_hy2:
            if not (raw_hy2.startswith('hysteria2://') or raw_hy2.startswith('hy2://')):
                raise ValueError('config.json 的 rawHy2Url 不是 hysteria2:// 或 hy2:// 开头')
            nodes.append(parse_hysteria2(raw_hy2, raw.get('hy2NodeName', '🇭🇰 Hysteria2')))
        if not nodes:
            raise ValueError('config.json 需要 rawVlessUrl 和/或 rawHy2Url (至少一个)')
        _cache['mtime'] = mtime
        _cache['raw_vless'] = raw_vless or None
        _cache['raw_hy2'] = raw_hy2 or None
        _cache['node_name'] = name
        _cache['singbox'] = json.dumps(build_singbox(nodes), indent=2, ensure_ascii=False)
        _cache['singbox_router'] = json.dumps(build_singbox(nodes, router_mode=True), indent=2, ensure_ascii=False)
        _cache['clash'] = build_clash(nodes)
    return _cache


class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        """Clash 等客户端会先 HEAD 探测，返回 200 即可"""
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain;charset=utf-8')
        self.send_header('profile-update-interval', '24')
        self.end_headers()

    def do_GET(self):
        try:
            c = get_configs()
            ua = self.headers.get('User-Agent', '').lower()
            qs = parse_qs(urlparse(self.path).query) if '?' in self.path else {}
            target = (qs.get('target', [''])[0] or '').lower()
            router = (qs.get('router', [''])[0] or '').lower() in ('1', 'true', 'yes')

            # /health
            if self.path == '/health':
                self._respond(200, 'OK', 'text/plain')
                return

            # sing-box (router=1 输出 auto_redirect + system 栈, 与 new.worker.js 对齐)
            if any(k in ua for k in ('sing-box', 'sfa', 'sfi', 'sfm')) or target == 'singbox':
                body = c['singbox_router'] if router else c['singbox']
                self._respond(200, body, 'application/json')
                return

            # Clash
            if any(k in ua for k in ('clash', 'mihomo', 'stash', 'clashverge')) or target == 'clash':
                self._respond(200, c['clash'], 'text/yaml')
                return

            # 默认 v2rayN base64 (vless/hy2 拼原始链接, 与 worker.js buildV2rayN 一致)
            raw_urls = []
            if c.get('raw_vless'):
                raw_urls.append(c['raw_vless'].strip())
            if c.get('raw_hy2'):
                raw_urls.append(c['raw_hy2'].strip())
            body = base64.b64encode('\n'.join(raw_urls).encode()).decode()
            self._respond(200, body, 'text/plain', extra={'Cache-Control': 'no-cache, no-transform'})

        except Exception as e:
            self._respond(500, f'subconverter error: {e}', 'text/plain')

    def _respond(self, status, body, ct, extra=None):
        body = body.encode() if isinstance(body, str) else body
        self.send_response(status)
        self.send_header('Content-Type', f'{ct};charset=utf-8')
        self.send_header('profile-update-interval', '24')
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass  # 静默日志


if __name__ == '__main__':
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
    port = cfg.get('port', 31001)
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
    # 预热缓存
    get_configs()
    print(f'subconverter v5.1 (python) ready on 127.0.0.1:{port}')
    srv.serve_forever()
