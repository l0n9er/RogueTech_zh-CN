param(
    [string]$mods = '',
    [string]$csv = '',
    [string]$backupRoot = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $game = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($game)) { throw '找不到游戏目录' }
    $mods = Join-Path $game 'Mods'
}
if ([string]::IsNullOrWhiteSpace($csv)) {
    $csv = Join-Path $packRoot 'strings_zh-CN.csv'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) {
    $backupRoot = Join-Path $packRoot 'backup\residual-candidates'
}

$enc = New-Object Text.UTF8Encoding $false
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$jsonChanged = 0
$jsonReplaced = 0
$csvChanged = 0

function Read-JsonString([string]$value) {
    try { return $ser.DeserializeObject('"' + $value + '"') }
    catch { return $null }
}

function Write-Backup([string]$path, [string]$old) {
    $fullPath = [IO.Path]::GetFullPath($path)
    $gameRoot = [IO.Path]::GetFullPath((Split-Path $mods -Parent)).TrimEnd([char]92) + [char]92
    $packageRoot = [IO.Path]::GetFullPath($packRoot).TrimEnd([char]92) + [char]92
    if ($fullPath.StartsWith($gameRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $fullPath.Substring($gameRoot.Length)
    } elseif ($fullPath.StartsWith($packageRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = Join-Path '_package' $fullPath.Substring($packageRoot.Length)
    } else {
        $rel = Join-Path '_external' (Split-Path $fullPath -Leaf)
    }
    $bak = Join-Path $backupRoot $rel
    $parent = Split-Path $bak -Parent
    if (-not (Test-Path $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $old, $enc) }
}

function Translate-EventGap([string]$rel, [string]$value) {
    $file = [IO.Path]::GetFileName($rel)

    $candidateTranslation = Translate-EventQaCandidates $file $value
    if ($null -ne $candidateTranslation) { return $candidateTranslation }

    if ($rel -match '(?i)^Flashpoints[\\/]FightingGhosts[\\/]mod\.json$' -and
        $value -eq 'The journey with the Gray Death Legion') {
        return '与灰死军团同行的旅程'
    }

    if ($value -match '^\s*["'']?I think we need to wait a (?<period>week|fortnight|month) before we jump into this to ensure our best chance at victory\.\s+We will revisit this in (?<days>\d+) days\.?["'']?\s*$') {
        switch ($Matches.period) {
            'week' { return '我认为最好等一周再跃迁过去，以确保胜算最大。一周后我们再重新评估。' }
            'fortnight' { return '我认为最好等两周再跃迁过去，以确保胜算最大。两周后我们再重新评估。' }
            'month' { return '我认为最好等一个月再跃迁过去，以确保胜算最大。一个月后我们再重新评估。' }
        }
    }

    if ($file -eq 'event_solarisSeasonStart4.json' -and
        $value -match '(?i)^\s*["'']?Purchase access to a Solaris 7 Championship["'']?\s*$') {
        return '购买索拉里斯7号锦标赛的参赛资格。'
    }

    if ($file -eq 'event_mw_KrakenMarked1.json') {
        if ($value -match 'is quarantined in one of the MedBays and provided a generic symptomatic treatment') {
            return @'
[[TGT_MW,{TGT_MW.Callsign}]] 被隔离在一间医疗舱内，接受常规的对症治疗。没过多久，[[SCN_MW,{SCN_MW.Callsign}]] 也来到医疗舱陪伴{TGT_MW.Callsign}；随后，[[TRT_MW,{TRT_MW.Callsign}]] 也病倒了。病毒尚未扩散，谣言和恐慌却传播得更快，毁容的脓疱、高烧不退和神志错乱等说法满天飞。每个人都开始向自己信奉的神明祈祷。最终，隔离成功控制了疾病传播。不过这三名机甲战士还需要很长时间才能康复。
'@
        }
        if ($value -match 'is quarantined in one of the MedBays and the medication administered') {
            return @'
[[TGT_MW,{TGT_MW.Callsign}]] 被隔离在一间医疗舱内并接受了药物治疗。很快，[[SCN_MW,{SCN_MW.Callsign}]] 也来到医疗舱陪伴{TGT_MW.Callsign}。病毒尚未扩散，谣言和恐慌却传播得更快，毁容的脓疱、高烧不退和神志错乱等说法满天飞。每个人都开始向自己信奉的神明祈祷。星球提供的药物发挥了作用，及时遏制住传染。没有其他人染病，但那三名感染的机甲战士仍将经历漫长而缓慢的康复期。
'@
        }
    }

    if ($file -eq 'event_mw_KrakenMarked.json') {
        if ($value.StartsWith(([string][char]34) + 'You''re talking to the wrong person, friend') -and $value -notmatch 'The leader shrugs') {
            return @'
“你们找错人了，朋友。”你对那伙人的头目说道，“[[TGT_MW,{TGT_MW.Callsign}]] 现在仍为我效力，都给我滚开。”

头目看着你，惊讶地睁大了眼睛。“辛迪加来要钱了，{TGT_MW.Firstname} 欠他们——”

你用手指戳着他的胸口。“错！{TGT_MW.Callsign} 已经不欠你们任何东西。我们和<i>首脑</i>有约，辛迪加只能等着。”你说道，“现在让开，我还有事。”

头目看着你：“你认识<i>首脑</i>？”随后他低下目光，侧身让开。你和{TGT_MW.Callsign}继续向前，趁他还没反悔。返回<i>阿尔戈</i>号的途中，这名机甲战士难得向你聊起了自己的过去。
'@
        }
        if ($value.StartsWith(([string][char]34) + 'You''re talking to the wrong person, friend') -and $value -match 'The leader shrugs') {
            return @'
“你们找错人了，朋友。”你对那伙人的头目说道，“[[TGT_MW,{TGT_MW.Callsign}]] 现在仍为我效力，都给我滚开。”

头目耸耸肩。“行啊。你想替{TGT_MW.Firstname}还债？随便。”

你挨了一脚，猝不及防地跪倒在地。{TGT_MW.Callsign}立刻扑向袭击者，双方随即打成一团。

几分钟后，所有打手都倒下了。{TGT_MW.Callsign}捂着侧腹，那里被人捅了一刀。“警察来了我们就麻烦了。”{TGT_MW.Subj}喘着气说。

等你们赶到穿梭机，一切都结束了，只剩下处理{TGT_MW.Callsign}的伤口。
'@
        }
    }

    if ($file -eq 'event_co_KrakenGoodReaper.json' -or $file -eq 'event_mw_KrakenGoodRigger.json') {
        if ($value.StartsWith('You are on the bridge when Sumire calls out')) {
            return @'
你正在舰桥上，苏米蕾喊道：“指挥官，有一段全息通讯呼入。”

你示意苏米蕾接通通讯。“指挥官{COMMANDER.LastName}，您好。您和{COMPANY.CompanyName}近来可好？一切都还顺利吧？”

你抱起双臂：“你还真是阴魂不散。这次又是谁欠了你的钱，<i>首脑</i>？”

<i>首脑</i>笑了笑，没有回答：“你最近在经营一项有趣的副业。我花了些时间才看清你的盘算，不过现在我知道你在做什么了。”

你靠回椅子：“那你倒说说，我在做什么？”

<i>首脑</i>拿出数据板，滑动着上面的记录：“亲爱的指挥官，你故意雇用罪犯，就是希望他们曾得罪辛迪加，好让我找上门来。”

你摆出最沉着的表情，思索片刻后答道：“我为什么要这么做？每次接到你的联络，我都恨不得把通讯掐断。而且，我还要抗议……”

<i>首脑</i>打断了你的话：“得了吧，指挥官。记录显示，你靠派飞行员参加比赛赚了几百万 C币。你偏爱雇用罪犯这件事，辛迪加早就注意到了，注意到的可不止我们。”

你冷冷地盯着<i>首脑</i>：“你经营的那场‘比赛’分明就是让参赛者送命，居然还敢指责我行为不端？你真是个伪君子。”

<i>首脑</i>阴险地笑了：“这就是你犯下的致命错误。我不必遵守和你一样的规则。你经营的是雇佣兵连队，最终要向雇佣兵评审委员会（MRBC）负责。你可以冒着声望受损的风险，也可以偿还你靠把某些船员送进那场‘比赛’赚来的部分钱款。想象一下，MRBC制裁你，连队评级跌破 300；他们若调查[[DEAD_MW,{DEAD_MW.Callsign}]]的遭遇，事情就更麻烦了。我劝你慎重选择，指挥官。”
'@
        }
        if ($value.StartsWith('You growl at <i>') -and $value -match 'you feel cheated') {
            return @'
你冲着<i>首脑</i>低吼：“让我弄清楚：你觉得我们雇用罪犯赚得比他们欠你的钱还多，所以现在要我们赔偿；否则你就向 MRBC 举报，声称我们虐待船员？真会倒打一耙。随你的便，想做什么就做什么；MRBC真要找麻烦，我们接着就是。”

<i>首脑</i>不悦地看着你：“看来你真以为我在虚张声势。辛迪加可不喜欢被人利用。我倒很想看看，MRBC联系你时，你会是什么表情。”全息通讯随即中断。达吕斯看着你担忧的神色：“指挥官，情况能有多糟？”
'@
        }
        if ($value -match '(?is)^You sit in silence staring long and hard at <i>(?:Front Man|前方 Man)</i>.*?owe the Syndicate\s+¢(?<owed>[\d,]+).*?round that down to ¢(?<offer>[\d,]+)') {
            $owed = $Matches.owed
            $offer = $Matches.offer
            $translated = @'
你默默地盯着<i>首脑</i>看了好一会儿，终于问道：“这要花多少钱？”

<i>首脑</i>移开视线，过了几秒才转回来：“让我算算……指挥官，你最近可真够忙的。总的来说，你欠辛迪加 ¢__OWED__。不过我挺喜欢你的，不如抹掉零头，算你 ¢__OFFER__，就此了结，怎么样？”

你看着这笔钱，脸色明显沉了下来：“我需要你保证，你和你的<i>辛迪加</i>都不会再来烦我们。”

<i>首脑</i>看起来很受伤：“可我真的很喜欢你，指挥官！你真要因为这点事结束我们的交情，坚持以后再也不和我们来往吗？”

“我们……不是……朋友！”你怒吼道，“如果付 ¢__OFFER__ 就能让你们离开，不再纠缠我和我的公司，那我很乐意。”

<i>首脑</i>从全息屏幕前转过身：“如你所愿，指挥官。”
'@
            return $translated.Replace('__OWED__', $owed).Replace('__OFFER__', $offer)
        }
    }

    if ($file -eq 'event_mw_KFCCrackx.json') {
        if ($value.StartsWith('You think over the offer [[TGT_MW,')) {
            return @'
你思索着[[TGT_MW,{TGT_MW.Callsign}]]带来的提议，问道：“达吕斯，我们现在负担得起这两种方案中的任何一种吗？”

达吕斯迅速查看数据板：“能负担得起，不过这笔开支没有列入预算，会让我们手头紧不少。除非你认为这是达成目标必不可少的一步，否则最好先等等，看看 CJSTA 那边接下来会怎样。”

你转向[[TGT_MW,{TGT_MW.Callsign}]]：“谢谢你把这个提议带来。你是个可靠的机甲战士。我想目前还是先婉拒，不让你以前的同伴卷进来。请替我谢谢他们；将来或许会有用得上他们本事的时候。”

[[TGT_MW,{TGT_MW.Callsign}]]笑着点头：“明白，指挥官。不过就像我刚才说的，我不想再走回那条老路。”[[TGT_MW,{TGT_MW.Callsign}]]站起身，递出一把数据钥匙：“指挥官，日后有需要的话，可以用这个联系他们。”

你示意达吕斯收下数据钥匙：“再次谢谢你，[[TGT_MW,{TGT_MW.Callsign}]]。”
'@
        }
        if ($value.StartsWith('You think over the offer put forth to you')) {
            return @'
你仔细考虑着这份提议，然后说道：“[[TGT_MW,{TGT_MW.Callsign}]]，谢谢你把这个提议带给我。你是个可靠的机甲战士，我知道要向你已经断绝关系的团体传递消息并不容易。我认为我们目前最好也和他们保持距离，不需要他们提供服务。”

[[TGT_MW,{TGT_MW.Callsign}]]笑着点头：“明白，指挥官。我会一如既往地效忠于你和{COMPANY.CompanyName}。”

达吕斯有些困惑，起身和[[TGT_MW,{TGT_MW.Callsign}]]一同离开。
'@
        }
    }

    if ($file -eq 'event_co_ReplacePartsKFC.json' -and
        $value -match '^\s*["'']?You ponder her query for a few minutes before responding') {
        return @'
你思索了几分钟，随后回答：“干得好，法拉。先让 KF 控制台保持<i>停用</i>，下一次跳跃我们继续使用常规航行。”<color=#FFA500> KF 控制台现已上线。</color>状态：<color=#FF0008>停用。</color>
'@
    }

    if ($file -eq 'event_mw_localFood.json') {
        if ($value.StartsWith('As the crew cautiously pokes at the mystery meat')) {
            return @'
船员们小心翼翼地尝着这道谜之肉食，[[TGT_MW,{TGT_MW.Callsign}]]却津津有味地大口吃着{TGT_MW.Det}那份。“烟熏味和甜味搭配得多棒啊！平时可不常有机会吃到既长毛<i>又</i>长羽毛的动物。当地猎人还告诉我，这种动物退化的后腿才是最好吃的部分——主要用来奔跑的腿太硬，根本嚼不动。”一顿饭下来，其他机甲战士也认同{TGT_MW.Callsign}带来的奇特动物确实美味，纷纷举手赞成这次尝试。
'@
        }
        if ($value -match '^As your (?:MechWarriors|机甲Warriors) serve themselves heaping portions of the mystery meat') {
            return @'
机甲战士们给自己盛了满满一盘谜之肉食，[[TGT_MW,{TGT_MW.Callsign}]]更是迫不及待地享用起{TGT_MW.Det}那份。“烟熏味和甜味搭配得多棒啊！平时可不常有机会吃到既长毛<i>又</i>长羽毛的动物。当地猎人还告诉我，这种动物退化的后腿才是最好吃的部分——主要用来奔跑的腿太硬，根本嚼不动。”没过多久，全体船员都在称赞这种动物的味道和口感，大家一致举手赞成这次尝试。
'@
        }
    }

    if ($file -eq 'event_mw_wealthyWeddings.json' -and $value.StartsWith('Apparently [[TGT_MW,')) {
        return @'
看来，[[TGT_MW,{TGT_MW.Callsign}]]对家族婚礼计划并不像最初说的那么重要。家族没有支付任何补偿金，这名机甲战士也无法成行，对此同样十分不满。
'@
    }

    if ($file -eq 'event_mw_disciplinaryMeasures.json' -and $value.StartsWith('Later that week, Darius reports in. "Well,')) {
        return @'
那周晚些时候，达吕斯前来汇报：“{COMMANDER.FirstName}，……看来[[TGT_MW,{TGT_MW.Callsign}]]确实没再进机甲库。可技师还是在走廊里‘意外’摔了个漂亮的跟头。他伤得不轻，不过大概一周左右就能复工。”
'@
    }

    if ($file -eq 'event_GhostsOfRetribution_GhostBearWatch_SelectRWROutpost11_1.json' -and $value.StartsWith('<color=#BFBFBF><i>Carath Prime</i> looms dry and red below')) {
        return @'
<color=#BFBFBF><i>卡拉斯主星</i>干燥赤红的地表在下方铺展开来。阳光灼烧着大地，坍塌的掩体则留下了一个早已破灭的梦想。这里曾是[[DM.Factions[faction_RimWorldsRepublic],环世界共和国]]一项偏远的军事计划所在地，如今被[[DM.Factions[faction_MinnesotaTribe],明尼苏达部落]]改造成训练与休整的熔炉。一座锻造场，掩埋在数百年的黄沙与沉寂之下。

一段安全的超脉冲通讯接入。星上校阿蕾尔·约根松出现在全息桌旁，神情沉着而坚定。</color>“部落出现在这里绝非偶然。他们正在培养军官、挖掘星盟遗迹，并为更大的行动做准备。我们不会让他们得逞。”

<color=#BFBFBF>她指向一组闪烁着目标标记的战术读数。</color>

“主要目标有三项。”

“第一，他们建立了一处学员训练场。新兵已经开始训练，教官也在现场。趁他们还没被部署出去，消灭他们。”

“第二，一支打捞队发现了一处被掩埋的[[DM.Factions[faction_SLDF],星盟防卫军（SLDF）]]设施。在部落转移或摧毁技术资料之前，把它们带回来。”

“第三，一座永久训练设施在他们控制之下。夺取它。我们需要那里的基础设施和情报。”

<color=#BFBFBF>她的语气变得严厉。</color>“三项行动都必须完成。先选一项，但选定后，你们只有十四天时间部署。拖延下去，我们就会失去先机。”

<color=#BFBFBF>通讯中断。下方的<i>卡拉斯主星</i>严酷而古老，如今又将成为战场。</color>
'@
    }

    if ($file -eq 'event_GhostsOfRetribution_MinnesotaTribe_ArelleReachesOut.json') {
        if ($value.StartsWith('<color=#BFBFBF>A priority signal cuts through the bridge comms')) {
            return @'
<color=#BFBFBF>一段优先级极高的信号毫无预警地切入舰桥通讯。它既没有经过部落的中继站，也不属于船员一直在使用的任何频道。</color> <color=#BFBFBF>法拉立刻坐直身体，手指已经在控制台上飞快操作。</color>“这是[[DM.Factions[faction_GhostBearWatch],守望者]]的军事频道，采用巡逻队级别的加密。没人应该通过这里联系我们。”

<color=#BFBFBF>信号解码后，屏幕上出现了一段简短文字，没有声音，也没有影像。</color> <color=#DFDFDF>“指挥官。我知道你和你那帮人一直在做什么，实在令我震惊。但只要你们迷途知返，加入胜利的一方，也就是我们这边，我愿意不再追究你们的过错。我只给你们这一次机会。一次。接受与否，悉听尊便。”——星上校阿蕾尔·约根松</color>

<color=#BFBFBF>达吕斯盯着屏幕。</color>“从第一次谈话开始，她就一直在监视、跟踪我们。我本来不该感到意外。”

<color=#BFBFBF>苏米蕾俯身又读了一遍讯息。</color>“不知怎么的，她知道我们对目前的处境并不满意。现在她通过军事线路联系我们，而不是私人频道。这是故意的。”

<color=#BFBFBF>法拉缓缓摇头。</color>“这个频道传输的是目标数据和巡逻命令。她用它发送私人讯息，就是要让我们知道她能接触守望者的行动基础设施。这是在提醒我们她掌控着什么。这里还有一条超脉冲链路，可以直接和她通话。”

<color=#BFBFBF>回应终端上的光标闪烁着。</color>
'@
        }
        if ($value.StartsWith('<color=#BFBFBF>You reach over and kill the signal')) {
            return @'
<color=#BFBFBF>你伸手切断信号，屏幕随即暗了下去。</color> <color=#BFBFBF>几秒钟里，没人说话。法拉把手从控制台上收回来。达吕斯仍拿着数据板看着你。</color>“好吧，指挥官。由你决定。只希望你清楚自己在做什么。”
'@
        }
        if ($value.StartsWith('<color=#BFBFBF>You look at the blinking cursor')) {
            return @'
<color=#BFBFBF>你盯着闪烁的光标看了好一会儿，然后站起身。</color>“我们接受。马上去会议室，所有人都过去。” <color=#BFBFBF>达吕斯张了张嘴，又闭上，随后拿起数据板。法拉把信号转接到会议终端，跟着你离开。杨和苏米蕾也很快加入队伍。</color>
'@
        }
    }

    if ($file -eq 'event_co_LRFletcher.json') {
        if ($value -match '^\s*["“”]?Darius,\s+accept the contract\.\s+Okay folks') {
            return @'
“达吕斯，接受合约。好了，各位，开工了！出发去守住那座工厂！”

[[SCN_MW,{SCN_MW.Callsign}]]走上前来：“指挥官，我想参加接下来的战斗。我们最终要重建<i>Last Rites</i>，我也想为{COMPANY.CompanyName}尽一份力。”

你点点头：“当然欢迎你参加，[[SCN_MW,{SCN_MW.Callsign}]]。”

<color=#FF0000>守卫基地合约：Last Rites，已添加到指挥中心</color>
'@
        }
    }

    if ($file -eq 'forceevent_co_LRVipaava_Failed.json' -and $value -match '^\s*["'']?Alright, we have another shot here') {
        return @'
好，这次我们还有机会。那就拿出顶尖雇佣兵连队的样子来！出发去把占据工厂的那群人赶出去！达吕斯，通知<i>Zoom N Boom</i>，我们又回来接任务了。<color=#FF0000>占领基地合约：Last Rites，已添加到指挥中心</color>
'@
    }

    if ($file -eq 'forceevent_co_LRRadstadt_Failed.json' -and $value -match '^\s*["'']?Darius, accept the contract\.') {
        return '<color=#FF0000>达吕斯，接受合约。你们还等什么？各就各位，我们回去继续干活。炸掉一堆东西有多难？</color> <color=#FF0000>伏击车队合约：Last Rites，已添加到指挥中心</color>'
    }
    if ($file -eq 'forceevent_co_LRRasalhague_Failed.json' -and $value -match '^\s*["'']?Darius, accept the contract\.') {
        return '<color=#FF0000>达吕斯，接受合约。你们还等什么？各就各位，我们回去继续干活。我们得拿下这座设施，终于把那台该死的机甲拼起来！</color> <color=#FF0000>攻防合约：Last Rites，已添加到指挥中心</color>'
    }
    if ($file -eq 'forceevent_co_LRFletcher_Failed.json' -and $value -match '^\s*["'']?Man, that is some dirty pool there\.') {
        return '<color=#FF0000>这手段真够阴的。他们至少该把骗局告诉我们。算了，我们还需要那个零件，所以不能和他们闹翻。达吕斯，接受合约。各位，出发，这次把工厂守好！</color> <color=#FF0000>守卫基地合约：Last Rites，已添加到指挥中心</color>'
    }
    if ($file -eq 'forceevent_co_LRGibbs_Failed.json' -and $value -match '^\s*["'']?Oh those sneaky bastards!') {
        return '<color=#FF0000>真是一群狡猾的混蛋！换了我也会这么干。达吕斯，接受合约。各位，出发，这次把车队守好了！</color> <color=#FF0000>护送车队合约：Last Rites，已添加到指挥中心</color>'
    }
    if ($file -eq 'forceevent_co_LRGalatea_Failed.json' -and $value -match '^\s*["'']?Well, who are we to look a gift mech') {
        return '<color=#FF0000>白送的机甲送到驾驶舱里，哪有不收的道理？达吕斯，接受合约。听好了，各位，我们再去一次，这回拿出专业水准！</color> <color=#FF0000>营救合约：Last Rites，已添加到指挥中心</color>'
    }
    if ($file -eq 'forceevent_co_LRNovaya_Failed.json' -and $value -match '^\s*["'']?Well, wonders never cease!') {
        return '<color=#FF0000>真是怪事年年有！达吕斯，接受合约，我们赶紧下去……还有车队等着拦截！</color> <color=#FF0000>伏击车队合约：Last Rites，已添加到指挥中心</color>'
    }

    if ($file -eq 'event_DeadMW_BaracasHacker.json' -and $value.StartsWith('You hand the datapad back to Yang,')) {
        $billMatch = [regex]::Match($value, 'Final bill came in at\s+¢(?<bill>[\d,]+)')
        if ($billMatch.Success) {
            $translated = @'
你把数据板递还给杨：“辛苦了，杨。联系他们，让这套<i>Rogue Bear 战斗装甲</i>恢复正常运作。”杨笑着接过数据板：“交给我，老板！”你听见他吹着口哨往机甲库走去。

过了一会儿，有人敲响办公室的门，杨走了进来：“老板，搞定了。现在任何有战斗装甲经验的人都能驾驶这套<i>Baracas</i>。”你笑道：“好消息。最后花了多少钱？”杨看了一眼手里的数据板：“最终账单是 ¢__BILL__ C币。”你皱了皱眉：“真贵！至少比他们暗示的少。还有别的要注意吗？”杨点头：“有，老板。解除生物锁后的<i>Baracas</i>性能达不到[[DEAD_MW,{DEAD_MW.Callsign}]]原先的水平。解锁过程损坏了作战套件，现在的功能更接近守护者 ECM。”
'@
            return $translated.Replace('__BILL__', $billMatch.Groups['bill'].Value)
        }
    }

    if ($file -eq 'fp_longagofaraway.json' -and $value -match '(?i)^A (?:距离urbance|disturbance) has overcome local Resources') {
        return '当地资源遭遇了一场骚动。仿佛数十亿 C 币同时哀嚎。'
    }
    if ($file -eq 'fp_robbingthecradle.json' -and $value -match '(?i)^What would you do f(?:或|or) love\?') {
        return '为了爱情，你愿意做到什么地步？'
    }
    if ($file -eq 'event_co_KFCBadaBoom.json' -and $value -match 'Repairs can wait f(?:或|or) now') {
        return '维修可以稍后再处理。'
    }
    if ($file -eq 'event_mw_solarisChampionship.json' -and $value -match '(?i)^Watch the .+ with them$') {
        return '和他们一起观看冠军赛。'
    }
    if ($file -eq 'event_solarisSeason.json' -and $value -match '(?i)^Purchase access to the .+ Opens$') {
        return '购买索拉里斯7号赛事的观赛资格。'
    }
    if ($file -eq 'fp_secondTry.json' -and $value -match '(?i)^The journey with .+ Legion$') {
        return '与灰死神军团的旅程。'
    }
    if ($file -eq 'SimGameStatDesc_KrakenChampionCount.json' -and $value -match '^Counter for number of .+ by Player$') {
        return '玩家获得的角斗士冠军次数。'
    }

    if ($file -eq 'event_mw_KrakenGoodRigger.json' -and
        $value.StartsWith('You sit in silence staring long and hard at')) {
        $transfer = [regex]::Match($value, 'Transfer the ¢(?<amount>[\d,]+) C币').Groups['amount'].Value
        if (-not $transfer) { return $null }
        $translated = @'
你沉默地盯着<i>幕后主使</i>看了许久，问道：“你真指望我直接掏出 ¢7,500,000 C 币？这可不是一笔能随手拿出来的钱！”

<i>幕后主使</i>移开视线片刻，随后转向你：“你知道，辛迪加必须杀一儆百，尤其是有人像你这样竭力逃避我们<i>游戏</i>的真正结果。所欠的金额就是这么多。”

你对这个数目明显不满：“我给你 ¢5,000,000。我还要你保证，绝不再报复或针对{TGT_MW.Callsign}。”

<i>幕后主使</i>盯着你看了许久：“我很欣赏你，指挥官，所以这样吧。转账 ¢__TRANSFER__ C 币，我们就放了{TGT_MW.Callsign}。此外，我们会彻底勾销{TGT_MW.Callsign}在辛迪加的所有债务。相信我们很快还会再见。”

<i>幕后主使</i>的影像随通讯切断而消失。
'@
        return $translated.Replace('__TRANSFER__', $transfer)
    }

    if ($file -eq 'event_mw_festivalOfLights.json' -and
        $value.StartsWith('The following morning, Darius pulls you aside.')) {
        return '次日清晨，达里斯把你叫到一旁：“昨晚真够疯狂的，{COMMANDER.FirstName}。可以肯定，船员们很享受这次放松。<i>阿尔戈号</i>到处都有人醉倒，杨还发现[[TGT_MW,{TGT_MW.Callsign}]]在他的传送带上睡着了。杨还说，机甲库这段时间恐怕不会有实质进展。正如他所说，他的大多数队员现在连咖啡都煮不好，更别提修理战斗机甲了。”'
    }

    return $null
}

function Translate-OneManBandResidual([string]$file, [string]$value) {
    if ($file -match '^event_co_OneManBand_R1(?:_\d+)?\.json$') {
        $button = [regex]::Match($value, '<i>(?<button>CIRCLE|SQUARE|TRIANGLE|STAR)</i>').Groups['button'].Value
        $player = [regex]::Match($value, '<color=#D4AF37><i>Player (?<id>\d+)</i></color>').Groups['id'].Value
        if ($button -and $player -and $value -match 'hums and fires a steady beam directly at the mirror') {
            $buttonZh = switch ($button) { CIRCLE { '圆形' } SQUARE { '方形' } TRIANGLE { '三角形' } STAR { '星形' } }
            return @'
<color=#bbbbbb>达里乌斯挥拳欢呼：“太好了！我做到了，指挥官。”

画面重新亮起，聚焦于[[SCN_MW,{SCN_MW.Callsign}]]。</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密游戏场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]迅速按下带有<i>__BUTTON__</i>符号的按钮。机甲战士身旁的激光器发出嗡鸣，向镜面射出一道稳定光束。光束击中镜面，撞击点亮起，边缘逐渐焦黑；随后激光穿透厚重的玻璃，熄灭了。

一股刺鼻气味弥漫在小房间里，灯光暗了下来，镜面恢复透明，显露出另一名处于相同境地的参赛者。不同的是，<color=#D4AF37><i>__PLAYER__号玩家</i></color>胸口被烧穿一个大洞，已经当场死亡。

通讯器再次响起：<color=#D4AF37>“__PLAYER__号玩家淘汰。203号玩家赢得本轮。”</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>你和达里斯异口同声地喊道：“{SCN_MW.SUBJ_C}做到了！”

你们勉强压住笑意，继续看着屏幕上的事态发展。</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密游戏场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]身后的门打开，两名全副武装、戴着面罩的守卫走进房间。他们解开束缚带，将[[SCN_MW,{SCN_MW.Callsign}]]扶起来。

[[SCN_MW,{SCN_MW.Callsign}]]看着其中一名守卫：“你们要带我去哪里？我不想再参加这种游戏了。”

守卫没有理会{SCN_MW.DET}恳求，押着{SCN_MW.OBJ}走出房间。他们穿过曲折的走廊，沿途经过许多紧闭的房门。

最后，他们在一扇漆着<i>203</i>的门前停下。门打开后，守卫示意[[SCN_MW,{SCN_MW.Callsign}]]进去。{SCN_MW.SUBJ}看了看守卫和他们的武器，只得不情愿地走进房间。

里面更像一间没有窗户的小隔间，只有一扇门、一张床、一个洗手池、一面镜子和一间厕所。

[[SCN_MW,{SCN_MW.Callsign}]]瘫坐在床上，喃喃说道：“看来在这一切结束之前，我都得待在这里……或者死在这里。”

通讯器里传来声音：<color=#D4AF37>“所有参赛者，下一轮将于明天开始。十五分钟后熄灯。”</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>达里斯看着你：“指挥官，这些游戏看起来纯粹靠运气，几乎不需要技巧。[[SCN_MW,{SCN_MW.Callsign}]]的胜算不太乐观。”

你疲惫地坐回椅子。[[SCN_MW,{SCN_MW.Callsign}]]仍然活着，这让你刚才欣喜不已；可{SCN_MW.DET}处境也可能在转眼间改变。你看向达里斯：“告诉船员，[[SCN_MW,{SCN_MW.Callsign}]]已经通过第一轮。希望后面的挑战也能顺利通过。”</color>
'@.Replace('__BUTTON__', $buttonZh).Replace('__PLAYER__', $player)
        }

        if ($button -and $player -and $value -match 'A low humming noise can be heard') {
            $buttonZh = switch ($button) { CIRCLE { '圆形' } SQUARE { '方形' } TRIANGLE { '三角形' } STAR { '星形' } }
            return @'
<color=#bbbbbb>达里乌斯挥拳欢呼：“太好了！我做到了，指挥官。”

画面重新亮起，聚焦于[[SCN_MW,{SCN_MW.Callsign}]]。</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密游戏场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]迅速按下带有<i>__BUTTON__</i>符号的按钮。激光器旁传来一阵低沉嗡鸣，但并非来自那台激光器。[[SCN_MW,{SCN_MW.Callsign}]]看向激光器，接着把其他按钮逐个按遍，却没有任何效果。镜面上有一点开始发亮，周围逐渐焦黑；一道红宝石色光束随即射出，正中[[SCN_MW,{SCN_MW.Callsign}]]的胸口。

[[SCN_MW,{SCN_MW.Callsign}]]的头猛地向后一仰，{SCN_MW.OBJ}脸上露出痛苦神情。{SCN_MW.OBJ}双眼颤动着合上，头无力地垂了下来。镜面恢复透明，显露出另一名处于相同境地的参赛者。不同的是，<color=#D4AF37><i>__PLAYER__号玩家</i></color>先是一脸震惊，随后意识到自己没有死，脸上转为释然。

通讯器再次响起：<color=#D4AF37>“203号玩家淘汰。__PLAYER__号玩家赢得本轮。”</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>你难以置信地张着嘴，盯着屏幕。达里斯的喊声打破了你的恍惚：“不——！”

你们勉强控制住情绪，继续看着屏幕上的事态发展。</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密游戏场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]身后的门打开，两名全副武装、戴着面罩的守卫推着手推车走进房间。他们解开束缚带，把[[SCN_MW,{SCN_MW.Callsign}]]的身体抬上推车，随后将{SCN_MW.OBJ}推出房间。

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>屏幕渐暗，取而代之的是<i>信号已中断</i>提示。

桌旁的通信面板响起<i>提示音</i>。你走过去查看，发现是一条自动短信，发信人似乎是<i>首脑</i>。

你点击<i>打开</i>阅读消息：

<color=#009988><i>谨致哀悼，{Commander.Lastname} 指挥官。既然您读到了这条消息，就说明[[SCN_MW,{SCN_MW.Callsign}]]没能在第一轮比赛中幸存。

请放心，{SCN_MW.DET}的债务已经全部还清，您不必再替{SCN_MW.DET}偿还任何款项。事实上，我们还会给您和船员留下一份安慰奖。[[SCN_MW,{SCN_MW.Callsign}]]乘坐我们的运输船离开时，我们留下了一只货箱。它通过磁力吸附在您的船体外侧，就在我们接走[[SCN_MW,{SCN_MW.Callsign}]]时使用的对接环外面。

可惜游戏没能进行完整场次，否则我们本可以赚更多钱，给您的奖品也会丰厚得多。

谨致问候，
首脑</i></color>

你抬起头看向达里斯。他说道：“指挥官，这些游戏看起来纯粹靠运气，几乎不需要技巧。我想，[[SCN_MW,{SCN_MW.Callsign}]]的生还机会本来就不大。”

你疲惫地靠回椅背：“通知船员，[[SCN_MW,{SCN_MW.Callsign}]]不会回来了。我们必须挺过去，继续工作。”达里斯离开后，你不禁想知道自己是否还会与<i>首脑</i>再次打交道。</color>
'@.Replace('__BUTTON__', $buttonZh).Replace('__PLAYER__', $player)
        }
    }

    if ($file -match '^event_co_OneManBand_R2(?:_\d+)?\.json$' -and
        $value -match 'wire snips closer' -and $value -match 'holo-feed screen flares bright white') {
        $wire = [regex]::Match($value, 'the (?<wire>RED|BLUE|BLACK|WHITE) wire').Groups['wire'].Value
        $eliminated = @([regex]::Matches($value, 'Players (?<ids>[\d, ]+\s+and\s+\d+) have been eliminated') | ForEach-Object { $_.Groups['ids'].Value.Trim() })
        if (-not $wire -or $eliminated.Count -lt 2) { return $null }
        $wireZh = switch ($wire) { RED { '红色' } BLUE { '蓝色' } BLACK { '黑色' } WHITE { '白色' } }
        $firstEliminated = ($eliminated[0] -replace '\s+and\s+', '、' -replace ',\s*', '、')
        $secondEliminated = ($eliminated[1] -replace '\s+and\s+', '、' -replace ',\s*', '、')
        $translated = @'
<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密游戏场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]颤抖着抬起手，将剪线钳移向四根导线中的一根。

<b><color=#D4AF37>“还剩20秒……”</color></b>

{SCN_MW.SUBJ_C}闭上{SCN_MW.DET}双眼，喃喃念着一句像是祈祷的话。

<b><color=#D4AF37>“还剩15秒……”</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]睁开{SCN_MW.DET}双眼，紧盯镜中导线的倒影，迅速逐一检查，希望能看出哪根才是正确答案。

<b><color=#D4AF37>“还剩10秒……”</color></b>

{SCN_MW.SUBJ_C}正要选择一根导线，这时……

<b><color=#D4AF37>“__ELIMINATED_1__号玩家已被淘汰。还剩7秒……”</color></b>

{SCN_MW.SUBJ_C}抓住__WIRE__导线，将剪线钳移到切口处……

<b><color=#D4AF37>“__ELIMINATED_2__号玩家已被淘汰。还剩3秒……”</color></b>

{SCN_MW.SUBJ_C}闭上{SCN_MW.DET}双眼，剪断了__WIRE__导线……

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>全息屏幕骤然亮起一片白光，扬声器里传来震耳欲聋的爆炸声。画面慢慢重新清晰起来：[[SCN_MW,{SCN_MW.Callsign}]]身首分离的尸体倒在血泊中。染血衬衫上的<color=#009988><i>203号选手</i></color>标记成了辨认{SCN_MW.SUBJ}身份的唯一依据。全息画面仍在闪烁，显然已被爆炸损坏。通讯器传来播报：<color=#D4AF37>“203号选手，淘汰。”</color>

你、达里斯、苏米蕾、穆拉德博士和杨目瞪口呆地盯着全息影像，随后你跌坐到办公桌前，低声骂了几句，声音小得几乎只有自己听见。

杨打破沉默：“这大概是我见过最愚蠢的事情！到底是谁想出这种游戏的？”

穆拉德博士强忍哽咽说道：“其实，历史上一直有类似的<i>游戏</i>。泰拉曾有一种叫<i>俄罗斯轮盘</i>的游戏，使用装有一发子弹的转轮手枪。参与者轮流把枪口对准对方，直到枪转到装有子弹的弹膛并击发。这类<i>游戏</i>的胜算也差不多，结果却是永久性的。环蛇座的历史书里还有另一个例子……”

杨打断他：“够了，博士！这游戏又蠢又荒唐。”

你桌旁的通信面板响起<i>提示音</i>。你走过去查看，发现是一条自动短信，发信人似乎是<i>首脑</i>。

你点击<i>打开</i>阅读消息：

<color=#009988><i>谨致哀悼，{Commander.Lastname} 指挥官。既然您读到了这条消息，就说明[[SCN_MW,{SCN_MW.Callsign}]]没能在第二轮比赛中幸存。

请放心，{SCN_MW.DET}的债务已经全部还清，您不必再替{SCN_MW.DET}偿还任何款项。事实上，我们还会给您和船员留下一份安慰奖。[[SCN_MW,{SCN_MW.Callsign}]]乘坐我们的运输船离开时，我们留下了一只货箱。它通过磁力吸附在您的船体外侧，就在我们接走[[SCN_MW,{SCN_MW.Callsign}]]时使用的对接环外面。

可惜游戏没能进行完整场次，否则我们本可以赚更多钱，给您的奖品也会丰厚得多。

谨致问候，
首脑</i></color>

你靠回椅背，感到精疲力尽。你原本为[[SCN_MW,{SCN_MW.Callsign}]]仍然活着而欣喜，此刻却只能担心{SCN_MW.DET}处境随时会改变。你望向达里斯：“告诉船员，[[SCN_MW,{SCN_MW.Callsign}]]没能通过第二轮，不会回来了。我们必须挺过去，继续工作。”达里斯离开后，你不禁想知道自己是否还会与<i>首脑</i>再次打交道。</color>
'@
        $translated = $translated.Replace('__WIRE__', $wireZh)
        $translated = $translated.Replace('__ELIMINATED_1__', $firstEliminated).Replace('__ELIMINATED_2__', $secondEliminated)
        return $translated
    }

    if ($file -match '^event_co_OneManBand_R3(?:_\d+)?\.json$' -and
        $value -match 'At the count of THREE, \[\[SCN_MW,\{SCN_MW\.Callsign\}\]\] throws \{SCN_MW\.DET\} hand out in the shape of') {
        $moves = [regex]::Match($value, 'shape of (?<player>ROCK|PAPER|SCISSORS)\..*?sees (?<opponent>ROCK|PAPER|SCISSORS)', [Text.RegularExpressions.RegexOptions]::Singleline)
        if (-not $moves.Success) { return $null }
        $winner = ($moves.Groups['player'].Value -eq 'ROCK' -and $moves.Groups['opponent'].Value -eq 'SCISSORS') -or
                  ($moves.Groups['player'].Value -eq 'SCISSORS' -and $moves.Groups['opponent'].Value -eq 'PAPER') -or
                  ($moves.Groups['player'].Value -eq 'PAPER' -and $moves.Groups['opponent'].Value -eq 'ROCK')
        if (-not $winner -or $value -notmatch 'YOU HAVE WON THE FINAL GAME') { return $null }
        $moveZh = @{ ROCK = '石头'; PAPER = '布'; SCISSORS = '剪刀' }
        $translated = @'
<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密竞技场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

数到三时，[[SCN_MW,{SCN_MW.Callsign}]]把{SCN_MW.DET}手摆成__PLAYER_MOVE__。{SCN_MW.SUBJ_C}看向<color=#D4AF37><i>99号选手</i></color>的手，发现对方出了__OPPONENT_MOVE__。胜利的喜悦涌上{SCN_MW.OBJ}心头。{SCN_MW.SUBJ}绷紧身体，抬头看向<color=#D4AF37><i>99号选手</i></color>，本以为会看到愤怒，迎接{SCN_MW.SUBJ}的却是温暖的笑容。

<color=#D4AF37><i>99号选手</i></color>轻笑道：“你玩得真好！能输给你，我深感荣幸。”随后郑重地鞠了一躬。

守卫走上前，举起手枪。<color=#D4AF37><i>99号选手</i></color>向他点头说道：“如果能到别处处理接下来的事，也免去这位‘冠军’更多痛苦，我会非常感激。”不等守卫回答，<color=#D4AF37><i>99号选手</i></color>便转身走向庭院唯一的出口。

<b><color=#D4AF37>“99号选手，淘汰。203号选手，您赢得了最后一场比赛。”</color></b>

喜悦的泪水顺着{SCN_MW.DET}脸颊流下。直到这一刻，{SCN_MW.SUBJ}才意识到自己赢了！

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>你和舰桥上的船员们异口同声地欢呼：“{SCN_MW.SUBJ_C}做到了！”

众人脸上都藏不住笑意，继续看着屏幕上的事态发展。</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密竞技场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]身后的门打开，一名身穿金色长袍的高大身影缓步走向{SCN_MW.OBJ}。<i>首脑</i>向[[SCN_MW,{SCN_MW.Callsign}]]伸出手：“干得好！真是漂亮的一仗！”

[[SCN_MW,{SCN_MW.Callsign}]]怀疑地看着<i>首脑</i>：“这场恶心的比赛终于结束了吗？”

<i>首脑</i>笑道：“当然！你的债务已经全部还清。事实上，辛迪加押注你获胜，赚了不少钱，所以他们会送你一份奖品，带回去交给你的指挥官。”

<i>首脑</i>仍伸着手。[[SCN_MW,{SCN_MW.Callsign}]]低头看了看，勉强与他握手：“快带我离开这个鬼地方！”

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>屏幕渐暗，取而代之的是<i>信号已中断</i>提示。[[SCN_MW,{SCN_MW.Callsign}]]赢下比赛、即将回来的消息让所有人起身欢呼。

你转向达里斯：“告诉船员，[[SCN_MW,{SCN_MW.Callsign}]]赢了，很快就会回来。”达里斯点头：“遵命，指挥官。”

桌上的通讯面板响起<i>提示音</i>。你走过去查看，发现是一条自动短信，发信人似乎是<i>首脑</i>。

你点击<i>打开</i>阅读消息：

<color=#009988><i>好消息，{Commander.Lastname} 指挥官！想必您已经看到全息影像：[[SCN_MW,{SCN_MW.Callsign}]]赢下了最后一轮，并加冕为“冠军”。

请放心，{SCN_MW.DET}的债务已经全部还清，您不必再替{SCN_MW.DET}偿还任何款项。作为冠军，[[SCN_MW,{SCN_MW.Callsign}]]赢得了参赛奖励。很快抵达的运输船会带来一只货箱，希望里面的东西对您有用，也值得您收下。

能邀请[[SCN_MW,{SCN_MW.Callsign}]]参赛是我们的荣幸。希望{SCN_MW.SUBJ}愿意接受未来的邀请，捍卫{SCN_MW.DET}冠军头衔。我们会再联系您，指挥官。

谨致问候，
首脑</i></color>

杨看着你：“你没开玩笑吧？他们还想让{SCN_MW.OBJ}再参加一次？”你揉着太阳穴，头痛起来：“杨，我只希望再也不用见到<i>首脑</i>。如果[[SCN_MW,{SCN_MW.Callsign}]]想去参加比赛，我们也拦不住{SCN_MW.OBJ}。”

杨仍然一脸愤怒：“那纯粹是自找苦吃。不过，那个货箱快到了，我去看看？”

你点头让杨去忙，随后走向达里斯等人：“来吧，我们去好好迎接[[SCN_MW,{SCN_MW.Callsign}]]回家！”</color>
'@
        return $translated.Replace('__PLAYER_MOVE__', $moveZh[$moves.Groups['player'].Value]).Replace('__OPPONENT_MOVE__', $moveZh[$moves.Groups['opponent'].Value])
    }

    if ($file -match '^event_co_OneManBand_R1(?:_\d+)?\.json$') {
        $normalized = $value.Replace('<i>前部 Man</i>', '<i>首脑</i>').Replace('<i>阿戈</i>号', '<i>阿尔戈号</i>').Replace('<color=#CC3311>信号丢失</i>', '<color=#CC3311>信号丢失')
        if ($normalized -ne $value) { return $normalized }
    }
    return $null
}

function Translate-EventQaCandidates([string]$file, [string]$value) {
    if ($file -eq 'forcedevent_FP_BreakingNews_BreakingNews.json' -and
        $value.Contains('The Knights of Caerbannog')) {
        return $value.Replace('The Knights of Caerbannog', '卡厄班诺格骑士团')
    }
    if ($file -eq 'forceevent_co_LRMech_B.json' -and
        $value.Contains('Magshot AP Gauss Rifles')) {
        return $value.Replace('Magshot AP Gauss Rifles', 'Magshot AP 高斯步枪')
    }

    $oneManBandTranslation = Translate-OneManBandResidual $file $value
    if ($null -ne $oneManBandTranslation) { return $oneManBandTranslation }
    if ($file -match '^event_co_OneManBand_R2(?:_\d+)?\.json$' -and
        $value.StartsWith('<color=#bbbbbb>Darius barges in through the open doorway')) {
        return @'
<color=#bbbbbb>达里斯推门闯进办公室，杨、苏米蕾和穆拉德博士跟在他身后。“指挥官，<i>首脑</i>的直播信号已经接通，[[SCN_MW,{SCN_MW.Callsign}]]的命运即将揭晓。”

你抬头看向众人：“把画面接到屏幕上，达里斯。大家都希望[[SCN_MW,{SCN_MW.Callsign}]]能闯过这一关。”

达里斯在办公室墙上大屏旁的终端输入信息：“指挥官，正在接收信号。”

黑屏闪动起来，模糊的画面逐渐清晰。[[SCN_MW,{SCN_MW.Callsign}]]和其他几名<i>选手</i>正被押着穿过走廊，每个人的衣服上都印着编号。

你们紧盯屏幕，屏息等待[[SCN_MW,{SCN_MW.Callsign}]]赢下这一轮，挺进最终决赛。</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密竞技场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]和其他<i>参赛者</i>沿着走廊前进。几名守卫押着他们，脸上戴着严实的面罩，让人想起 DEST 突击队的士兵。

队伍每走一段便会停下，一名选手随即被带进房间。终于轮到[[SCN_MW,{SCN_MW.Callsign}]]。{SCN_MW.SUBJ_C}环顾四周，房间只有四面空墙和一块镜子。幸好这里没有椅子和激光手枪，{SCN_MW.SUBJ}知道这次玩的会是另一种游戏。

守卫从背包里取出一个环形装置。圆环一侧带有铰链，四根不同颜色的导线从环上连到一个盒子。守卫打开圆环，走到[[SCN_MW,{SCN_MW.Callsign}]]身边，将它扣在{SCN_MW.DET}脖子上；随后把盒子夹到{SCN_MW.DET}腰带上，四根导线沿着胸口接到颈环。

守卫离开房间，扬声器里传来声音：<color=#D4AF37>“欢迎各位参加下一场游戏。今天的项目名叫<i>炸弹大作战</i>。你们必须拆除颈部线圈里的炸弹：剪断从触发器通往线圈的其中一根导线。剪对了，装置就会解除。你们有 60 秒时间。倒计时开始……现在！”</color>

天花板打开，一把剪线钳掉在地上。[[SCN_MW,{SCN_MW.Callsign}]]迅速捡起剪线钳，走到镜子前仔细检查每根导线，试图判断该剪哪一根。

<color=#D4AF37>“剩余时间：30 秒”</color>

[[SCN_MW,{SCN_MW.Callsign}]]盯着镜中的自己，闭上{SCN_MW.DET}双眼。{SCN_MW.SUBJ_C}重新睁眼，把剪线钳举向……

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>
达里斯冲着屏幕大喊：“剪红线！”

杨看向达里斯：“你疯了吗？该剪的是黑线。”

苏米蕾笑道：“显然应该剪白线。”

穆拉德博士想了想，说：“我会剪蓝线。”</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密竞技场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]把剪线钳移到导线旁，决定剪下……
'@
    }

    if ($file -match '^event_co_OneManBand_R3(?:_\d+)?\.json$' -and
        $value.StartsWith('<color=#bbbbbb>You start to leave your office')) {
        return @'
<color=#bbbbbb>你正要离开办公室，迎面碰上达里斯、杨、苏米蕾和穆拉德博士。

达里斯示意你回办公室：“指挥官，<i>首脑</i>正在准备直播[[SCN_MW,{SCN_MW.Callsign}]]参加的最后一场比赛。”

你转身招呼众人跟上：“把画面接到屏幕上，达里斯。大家都希望[[SCN_MW,{SCN_MW.Callsign}]]能闯过最后的挑战。”

达里斯在办公室墙上大屏旁的终端输入信息：“指挥官，正在接收信号。”

黑屏闪动起来，模糊的画面逐渐清晰。[[SCN_MW,{SCN_MW.Callsign}]]和其他几名选手站在一处庭院里，每个人的衣服上都印着编号。

众人盯着屏幕，杨大喊：“加油，[[SCN_MW,{SCN_MW.Callsign}]]！你一定行！”</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密竞技场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

[[SCN_MW,{SCN_MW.Callsign}]]站在庭院里，身边是{SCN_MW.DET}其他参赛者。四周到处都是守卫，他们仍戴着遮住整张脸的面罩。

铃声响起，通讯频道里传来播报：“欢迎各位参加下一场游戏。本轮两人一组，请现在选择对手。”

一名魁梧的大汉走到[[SCN_MW,{SCN_MW.Callsign}]]面前，衬衫上印着<color=#D4AF37><i>5号选手</i></color>。“你来当我的对手。”[[SCN_MW,{SCN_MW.Callsign}]]看着这个比{SCN_MW.OBJ}高出一大截的男人，犹豫了一下，但其他人都已经配好对。{SCN_MW.SUBJ_C}耸耸肩，点头答应。

扬声器再次响起：“既然各位都配好对了，游戏现在开始。今天的项目叫作<i>猜拳</i>。”

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</b></color>

<color=#bbbbbb>杨皱眉道：“他们说的什么‘猜拳’？到底是什么玩意儿？”

穆拉德博士解释道：“这是泰拉的一种古老儿童游戏。孩子们用它解决争执，有些地方的成年人也会玩。”

苏米蕾问：“你知道规则吗？”

“知道。我小时候玩过，更多是为了比赛取乐，不是真的要解决争端。”穆拉德博士说，“我长大的地方叫它‘石头、剪刀、布’。规则很简单：双方面对面，一边握拳在身前摆动，一边数到三。数到三时，各自迅速摆出一种手势：握紧拳头是石头，摊开手掌是布，伸出食指和中指、其余手指收进掌心就是剪刀。手势之间有相克关系，胜负由此决定。”

杨插话道：“这游戏真蠢，石头每次都赢！”

穆拉德博士摇头：“并不是。石头能砸碎剪刀，剪刀能剪破布，布能包住石头。”

你思索片刻：“所以[[SCN_MW,{SCN_MW.Callsign}]]得挑一个对手，想办法看穿对方，或者吓得对方选出较弱的手势？”

达里斯怀疑地看着屏幕：“我不知道，指挥官。这看起来还是纯靠运气的游戏。”</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密竞技场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

播报继续：“双方各伸出一只握紧的手，数到三后同时出拳。握拳是石头，摊开手掌是布，伸出两根手指组成 V 形、其余手指收进掌心就是剪刀。石头胜剪刀，剪刀胜布，布胜石头。获胜者继续两两对决，直到只剩一名胜者，他将成为‘冠军’。拒绝比赛即视为弃权。游戏开始……现在！”

[[SCN_MW,{SCN_MW.Callsign}]]盯着<color=#D4AF37><i>5号选手</i></color>。两人伸出手，开始倒数：

一……二……三……[[SCN_MW,{SCN_MW.Callsign}]]出了石头，<color=#D4AF37><i>5号选手</i></color>出了剪刀。

[[SCN_MW,{SCN_MW.Callsign}]]冷冷一笑：“看来是我赢了。”<color=#D4AF37><i>5号选手</i></color>怒吼着扑向[[SCN_MW,{SCN_MW.Callsign}]]，一名守卫立刻上前开枪，子弹击中<color=#D4AF37><i>5号选手</i></color>的胸口，当场将他击毙。

播报响起：“<color=#D4AF37><i>203号选手</i></color>获胜。请寻找下一名对手，继续比赛。”

[[SCN_MW,{SCN_MW.Callsign}]]又找到一名选手并赢下比赛。{SCN_MW.SUBJ_C}连续赢了五轮，最终只剩下一名对手：一个身材高瘦、像僧侣一样的男人，戴着厚重的大眼镜，衬衫上印着<color=#D4AF37><i>99号选手</i></color>。

[[SCN_MW,{SCN_MW.Callsign}]]走上前时，<color=#D4AF37><i>99号选手</i></color>伸出手：“愿今天好运眷顾我们。”[[SCN_MW,{SCN_MW.Callsign}]]与他握手：“也祝你好运。”

两人面对面站定，开始倒数：

一……二……三……[[SCN_MW,{SCN_MW.Callsign}]]出了石头，<color=#D4AF37><i>99号选手</i></color>也出了石头，平局。

<color=#D4AF37><i>99号选手</i></color>鞠躬后重新倒数：

一……二……三……[[SCN_MW,{SCN_MW.Callsign}]]出了剪刀，<color=#D4AF37><i>99号选手</i></color>也出了剪刀，还是平局。

[[SCN_MW,{SCN_MW.Callsign}]]平静地看着对方，<color=#D4AF37><i>99号选手</i></color>也报以微笑。两人再次开始。

一……二……三……[[SCN_MW,{SCN_MW.Callsign}]]出了布，<color=#D4AF37><i>99号选手</i></color>也出了布，又一次平局。

<color=#D4AF37><i>99号选手</i></color>轻笑道：“呵呵，你可真聪明。确实是个值得尊敬的对手。”两人再次开始倒数：

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</b></color>

<color=#bbbbbb>
达里斯冲着屏幕大喊：“出布！”

杨瞪着达里斯：“你真蠢！明明石头才是最佳选择。”

苏米蕾笑道：“我这时候会出剪刀。穆拉德博士，你觉得呢？”

穆拉德博士想了想：“我还是不掺和了，免得把好运气说没了。”</color>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密竞技场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

一……二……三……[[SCN_MW,{SCN_MW.Callsign}]]把{SCN_MW.DET}手摆成……
'@
    }

    if ($file -match '^event_co_OneManBand_R3(?:_\d+)?\.json$' -and
        $value -match 'At the count of THREE, \[\[SCN_MW,\{SCN_MW\.Callsign\}\]\] throws his hand out in the shape of') {
        if ($value -match 'shape of ROCK\.\s+\{SCN_MW\.SUBJ_C\}.*sees PAPER') {
            $playerMove = '石头'; $opponentMove = '布'
        } elseif ($value -match 'shape of SCISSORS\.\s+\{SCN_MW\.SUBJ_C\}.*sees ROCK') {
            $playerMove = '剪刀'; $opponentMove = '石头'
        } elseif ($value -match 'shape of PAPER\.\s+\{SCN_MW\.SUBJ_C\}.*sees SCISSORS') {
            $playerMove = '布'; $opponentMove = '剪刀'
        } else { return $null }
        $translated = @'
<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color><color=#009988><i>[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上的秘密竞技场</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::</color></b>

数到三时，[[SCN_MW,{SCN_MW.Callsign}]]把手摆成__PLAYER_MOVE__。{SCN_MW.SUBJ_C}看向<color=#D4AF37><i>99号选手</i></color>的手，发现对方出了__OPPONENT_MOVE__。[[SCN_MW,{SCN_MW.Callsign}]]的手微微发抖，抬头望向<color=#D4AF37><i>99号选手</i></color>。{SCN_MW.SUBJ}本以为会看到对方松一口气，没想到<color=#D4AF37><i>99号选手</i></color>却失望地摇了摇头。

<color=#D4AF37><i>99号选手</i></color>看着[[SCN_MW,{SCN_MW.Callsign}]]：“真遗憾。我一直希望你能赢下比赛，接替我成为冠军。”

守卫走上前，<color=#D4AF37><i>99号选手</i></color>对他说：“{SCN_MW.SUBJ_C}值得尊重，也值得荣誉。”没等守卫回答，<color=#D4AF37><i>99号选手</i></color>便转身走向庭院唯一的出口。

守卫把爆能枪收回枪套，从腰带上取出一个罐子，朝[[SCN_MW,{SCN_MW.Callsign}]]脸上喷出一小股雾气。[[SCN_MW,{SCN_MW.Callsign}]]猝不及防地深吸一口气，{SCN_MW.DET}双眼颤动，随后倒在地上。守卫俯身检查脉搏，又招手叫来庭院另一侧的两名医护人员。

<b><color=#D4AF37>“203号选手，淘汰。”</color></b>

<b><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color><color=#009988>回到<i>阿尔戈号</i></color><color=#33bbee>::::::::::::::::::::::::::::::::::::::::::::::::::</color></b>

<color=#bbbbbb>屏幕暗了下去，随后显示出<i>信号已中断</i>。

你张着嘴，难以置信地盯着屏幕。

达里斯的喊声打破沉默：“不——！”

杨愤怒地把手里的廷比基干酒摔向墙壁。苏米蕾和穆拉德博士抱在一起，泪流满面。

桌上的通讯面板响起<i>提示音</i>。你走过去查看，发现是一条自动发送的短信，发信人似乎是<i>首脑</i>。

你点击<i>打开</i>，读起短信：

<color=#009988><i>谨致哀悼，{Commander.Lastname} 指挥官。既然你读到了这条消息，就说明[[SCN_MW,{SCN_MW.Callsign}]]没能在最后一轮比赛中幸存。

{SCN_MW.DET}债务已经全部结清，我们不会再向{SCN_MW.OBJ}追讨任何款项。事实上，我们还会给你和船员们一份安慰奖。[[SCN_MW,{SCN_MW.Callsign}]]乘坐我们的空投艇离开时，我们留下了一只货箱。它被磁力固定在你们船体外侧，就在我们接走[[SCN_MW,{SCN_MW.Callsign}]]所用的对接口附近。

可惜比赛没能进行到底，否则我们本可以赚得更多，你们的奖品也会丰厚得多。

谨上，
首脑</i></color>

你抬头看向达里斯。他说道：“指挥官，这些比赛看来纯粹靠运气，几乎没有技巧可言。我觉得[[SCN_MW,{SCN_MW.Callsign}]]能活下来的机会不大。”

杨怒斥达里斯：“说得倒轻巧。”

这场煎熬的比赛让你精疲力尽。你靠回椅背，对众人说道：“通知船员，[[SCN_MW,{SCN_MW.Callsign}]]不会回来了。我们得走出这件事，继续做好自己的工作。”

大家离开后，你不禁想知道自己是否还会与<i>首脑</i>再次相遇。</color>
'@
        return $translated.Replace('__PLAYER_MOVE__', $playerMove).Replace('__OPPONENT_MOVE__', $opponentMove)
    }

    if ($file -eq 'event_co_KFCKnockKnockKnocking.json' -and
        ($value -match 'foremost expert on ancient DropShips' -or $value -match 'tenacity in looking into this is commendable')) {
        if ($value -match 'Gear_FuCapacitor|Fu Capacitor') {
            $component = '[[DM.UpgradeDefs[Gear_FuCapacitor],Fu 电容器]]'
        } elseif ($value -match 'Gear_KerbyInjectors|Kerby Injectors') {
            $component = '[[DM.UpgradeDefs[Gear_KerbyInjectors],Kerby 喷射器组]]'
        } elseif ($value -match 'Cheatah Nav Computer') {
            $component = '<i>Cheatah 导航计算机</i>'
        } else { return $null }
        if ($value -match 'foremost expert on ancient DropShips') {
            $opening = '“您是外缘星域最了解古代空投艇的专家。若有人能解决这个问题，那一定是您。”你通过对讲机对穆拉德博士说道。'
            $ending = '你打了个大哈欠：“让夜班的少尉盯着它。我们先回去睡觉，需要时再处理。”'
        } else {
            $opening = '“您坚持调查这件事，实在令人佩服。我相信您一定能找到办法查明原因。”你通过对讲机对穆拉德博士说道。'
            $ending = '你打了个大哈欠：“我先回去睡了。继续留意情况，出了问题就通知我。”'
        }
        return @'
__OPENING__

穆拉德博士回答：“我知道声音来自<i>导航室</i>里的某样设备。周围杂音太多，很难确定源头，我也说不上来具体是什么。如果找不到原因，指挥官，大家今晚恐怕都睡不好。”

Kerby-FuCheetah 控制台附近传来一声更响的撞击。穆拉德博士走过去查看：“哦，这倒有意思！”

你问：“查到原因了吗？”

穆拉德博士有些惊讶：“或许查到了，指挥官。我怀疑问题出在刚安装的控制台上。简单检查后发现，__COMPONENT__可能已经故障。我晃了晃它，声音暂时停了。”

__ENDING__
'@.Replace('__OPENING__', $opening).Replace('__COMPONENT__', $component).Replace('__ENDING__', $ending)
    }

    if ($file -match '^event_DeadMW_BaracasCollector(?:_S)?\.json$' -and
        ($value.StartsWith('You finish your drink, grab the datapad') -or $value.StartsWith('你喝完酒，拿起数据板'))) {
        $amounts = @([regex]::Matches($value, '¢\s*([\d,]+)') | ForEach-Object { $_.Groups[1].Value })
        if ($amounts.Count -lt 6) { return $null }
        $translated = @'
你喝完酒，拿起数据板，又给杨买了一轮酒。“杨，辛苦了。我会联系那位收藏家，把这套战斗装甲卖掉。”

回到办公室后，你在桌前坐下，把数据板接到通讯终端，打开上面唯一的联系人记录，按下<i>接通</i>。等待片刻后，屏幕上的<i>正在连接</i>消失，出现一间极尽奢华的休息室。落地窗外是[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]上一座大都市的景色。似乎没有声音传来，画面里也看不到人。“有人吗？”你问。

背景里传来一阵响动，画面随即转向一个藏在阴影中的身影。“您好，{COMMANDER.LastName} 指挥官。谢谢您回复我。”

你盯着屏幕，心想<i>有钱人真奇怪</i>，随即回过神来：“呃，没关系，先生……怎么称呼？”

那人轻笑一声：“指挥官，不必知道我的名字。我不能让竞争对手知道我从哪里收集这些珍品，想必您能理解。我们直入正题吧。正如我告诉您同伴的，我愿以 ¢__M0__ C币购买<i>巴拉卡斯</i>，也就是前星蝰氏族可汗[[DEAD_MW,{DEAD_MW.Callsign}]]那套定制版流浪熊战斗装甲。”

你差点笑出声，赶紧忍住：“先生，恕我直言，开价是 ¢__M1__ C币。”

沉默仿佛持续了很久，那人终于开口：“¢__M2__ C币。”

你想起先前喝下的那杯[[DM.BaseDescriptionDefs[LoreGBL],格伦加里黑标威士忌]]，鼓起勇气坚持道：“这是一套独一无二的战斗装甲，还有其他买家感兴趣。我们的价格是 ¢__M3__ C币。”

那人毫不犹豫地向前倾身：“祝您找到其他买家，指挥官。再见。”

你赶在对方挂断前大声喊道：“¢__M4__ C币。我还得经营一家雇佣兵公司。”

阴影中的人靠回座椅：“¢__M5__ C币，这是我的最终报价，指挥官。”

你不想错失这笔交易，便接受了最终报价。接下来的几个小时里，你一直在签署电子文件，完成交易。
'@
        for ($i = 0; $i -lt 6; $i++) { $translated = $translated.Replace(('__M' + $i + '__'), $amounts[$i]) }
        return $translated
    }

    if ($file -eq 'Rescue_Superheavy_TheMissingVIP.json' -and $value.StartsWith('<b>Sender:</b>')) {
        return '<b>发件人：</b> <i>{TEAM_EMP.FactionDef.Name} 的雇佣兵评审委员会代表</i><br><b>收件人：</b> <i>{COMPANY.CompanyName} 雇佣兵连队指挥官 {COMMANDER.LastName}</i><br><b>主题：</b> <i>可承接合同</i><br><br><br><b>主要目标：</b> 执行营救行动，找回被{TEAM_TAR.FactionDef.Demonym}部队非法扣押为人质的重要人物。<br><br><b>次要目标：</b> 取回据称由该重要人物持有的公文包，其中包含对客户至关重要的机密信息。<br><br><b>任务详情：</b> 雇佣兵连队须派遣由熟练机甲战士、战术人员和支援人员组成的特遣队执行营救任务。小队必须潜入敌方控制区，找到重要人物并迅速果断地将其救出；优先保障其安全，不得为了公文包危及目标。<br><br><b>威胁评估：</b> 预计目标地点防守严密，需要采用先进的作战策略。情报显示当地有敌方巡逻队，可能还部署了数台超重型单位。雇佣兵连队必须准备应对常规和非对称威胁。<br><br><b>交战规则：</b> 雇佣兵连队获准采取一切必要手段完成任务，包括武装交战、隐蔽行动以及适当情况下的外交谈判。保护重要人物的生命是首要任务，取回公文包仅为次要目标。<br><br><b>时限：</b> 合同规定了严格的营救期限。雇佣兵连队必须在指定时间内完成行动，确保重要人物安全、及时撤离；只有在行动条件允许时，才尝试取回公文包。<br><br><b>报酬：</b> 完成主要目标后，雇佣兵连队将获得事先商定的资金和打捞份额，并可根据表现及任务执行情况获得奖金。是否为完成次要目标追加报酬，由客户决定。<br><br><b>保密要求：</b> 本合同的所有内容，包括任务详情、客户身份和行动信息，均属机密。雇佣兵连队必须谨慎行事，并在合同有效期间严格保密。<br><br><b>合同条款：</b> 本合同具有法律约束力，具体条款由客户与雇佣兵连队协商一致。任何偏离约定条款的变更，都必须记录在案并由双方书面批准。<br><br><br><b>客户授权码：</b> [MRB-SC-4876-936-5618-D]'
    }

    if ($file -eq 'GoR_MinnesotaTribe_AmbushConvoy_BrokenChains.json' -and $value.StartsWith('Star Captain Marcus Hammerick has identified')) {
        return '星队长马库斯·哈默里克发现，[[DM.Factions[faction_RemembranceCell],追忆小队]]的一支车队正押送阿妮卡·蒂尔赛博士，从她位于<i>阿贡代尔</i>的研究设施前往更安全的地点。数月前，蒂尔赛博士从<i>赖尔森</i>被劫走，如今正被迫参与武器研发。\n\n在车队抵达目的地前拦截他们。运输车上装有加固的 VIP 收容舱，即使车辆被摧毁，她也能活下来。'
    }

    if ($file -eq 'event_GhostsOfRetribution_GhostBearWatch_AshesSettled.json' -and
        $value -match 'The mech bay still smells like burned coolant') {
        return @'
<color=#BFBFBF><i>阿尔戈号</i>静默地继续绕行<i>布茨弗莱斯·大角星</i>。机甲库里仍弥漫着冷却液烧焦和装甲灼损的气味。晚餐时，船员们有一搭没一搭地吃着口粮，杨靠在隔板旁，最先打破沉默。</color>“囚犯。他在运送囚犯去修筑碉堡。那些人被迫待在冰天雪地的鬼地方服劳役，只因狱卒觉得他们作为劳工比作为囚犯更有价值。”<color=#BFBFBF>他摇了摇头。</color>“我接过一些活儿，雇员和苦役之间的界线都快模糊了。但这次不是模糊，而是根本没有界线。”<color=#BFBFBF>达里乌斯放下杯子。</color>“击杀干净利落，真正让我在意的不是这个，而是这件事到底能不能改变什么。鲁克只是中间人。部落需要劳工，他就负责提供。我们除掉他，他们还会找别人。换一个狱卒，换一个良心可以变通的边疆总督。只除掉一个供应者，需求并不会消失。”<color=#BFBFBF>还没等其他人回应，苏米蕾就在舰桥控制台上发现一条呼入通讯。又是一条来自[[DM.Factions[faction_GhostBearWatch],幽灵熊守望组织]]的加密信号。她把内容念了出来。</color><color=#DFDFDF>“鲁克已被清除。向[[DM.Factions[faction_MinnesotaTribe],明尼苏达部落]]输送劳工的渠道已经中断。下一个目标：天鹅座星系。预计敌对活动将会增加。抵达后提供完整任务简报。”</color><color=#BFBFBF>苏米蕾盯着屏幕看了一会儿。</color>“劳工输送渠道已经中断。她就是这么说的。不是解救了囚犯，也不是救出了人质，而是劳工输送渠道，仿佛只要关掉一条原材料供应线就行了。”<color=#BFBFBF>没有人反驳，也没有人表示异议。</color>
'@
    }

    if ($file -eq 'event_GhostsOfRetribution_GhostBearWatch_WarfrontRebalanced.json' -and
        $value -match 'A new Hyperpulse message appears at the') {
        return @'
<color=#BFBFBF>一条新的超光速脉冲通讯出现在<i>阿尔戈号</i>的通讯控制台上，标记为守望组织加密，标题是“<b>优先级战略通报</b>”。苏米蕾眉头一挑，立即截取了信号。</color>

“消息来自阿蕾尔的行政团队，”<color=#BFBFBF>她一边解密一边说道。</color>“这是一份全战区部署报告，特别通报。”

<color=#BFBFBF>报告内容以清晰、条理分明的方式显示在全息桌上。

[[DM.Factions[faction_GhostBearWatch],幽灵熊守望组织]]已成功完成在<i>星团752</i>、<i>Horgens</i>和<i>11号前哨站</i>的行动。三个星系现已确保安全并归守望组织管辖，移交工作正在进行，战术网络也已重新建立。

但这份报告不只是一份胜利清单。

除上述进展外，报告还显示，[[DM.Factions[faction_MinnesotaTribe],明尼苏达部落]]同时控制了周边多个区段的大量跃迁点，包括咽喉要道、交通门户，甚至曾被认为已经废弃的隐蔽航线。这些地点并非为了回应守望组织的行动而夺取，而是更大计划的一部分，并行实施。

守望组织现将几个相邻星系划为“<b>拒止区</b>”，实际上切断了一个不断扩大的太空区域，使其无法进行常规行动。

苏米蕾快速敲击几下按键，电脑随即发出一连串提示音。</color>“星图已更新，所有信息都已记录并核验。”

达里斯微微皱眉看着你：“指挥官，接下来有什么计划？”
'@
    }

    if ($file -eq 'event_GhostsOfRetribution_MinnesotaTribe_TheLastStep.json' -and
        $value -match 'The perimeter is breached') {
        return @'
<color=#BFBFBF>防线已被突破。[[DM.Factions[faction_RemembranceCell],追忆小队]]的守军散落在冰封荒野中。机甲战士们精疲力竭，但没有时间休息。</color>

<color=#BFBFBF>达里斯调出损伤评估。</color>“老板，我们情况很糟。装甲受损，船员疲惫。我们将在远非理想的状态下迎战下一场战斗。”

<color=#BFBFBF>暴雪中，生产设施已隐约出现在前方。乔安娜·麦克埃维迪和末日武器就在里面的某处。</color>

<color=#BFBFBF>通讯器中传来马库斯的声音。</color>“指挥官，我们结束这一切吧。现在就摧毁原型机，否则我只能引爆弹头。另一边见。”

<color=#BFBFBF>最终决战现在开始。</color>
'@
    }

    if ($file -eq 'LoreBlazerLaserPistol.json' -and
        $value.StartsWith('The Blazer 激光手枪 is a pistol version')) {
        return 'Blazer 激光手枪是广受欢迎的 Blazer 激光步枪的手枪版本。它的外形像一支锯短枪管的霰弹枪，沿用了步枪上相同的双激光管设计，能以小得多的体积提供同样惊人的火力。也正因此，这种手枪在许多内星区世界遭到禁售。两组能源包足以提供五次射击所需的能量；枪管也可以分开单独击发，此时 Blazer 的功能就与标准激光手枪相同。'
    }

    if ($file -eq 'event_GhostsOfRetribution_GhostBearWatch_DiplomaticFallout.json' -and
        $value.StartsWith('<color=#BFBFBF>Just as you are about to settle for a peaceful dinner')) {
        return @'
<color=#BFBFBF>你刚准备在餐厅安稳地吃顿晚饭，一条高优先级消息便传了进来。全息通讯抬头显示，这是一封来自<i>杜尼安郡六号</i>星球监察办公室的正式公函，隶属于<i>[[TGT_SYSTEM.OwnerDef,{TGT_SYSTEM.OwnerDef.Demonym}]]政权</i>。发言者是一名身材高挑、五官凌厉的女性，身穿玫瑰金色的{TGT_SYSTEM.OwnerDef.Demonym}官员制服。她举止从容、仪态得体，显然正在照稿宣读。</color><color=#DFDFDF>“{COMPANY.CompanyName} 连队指挥部：特此正式通知，贵部队在{TGT_SYSTEM.OwnerDef.Name}领土管辖范围内擅自发起了未经批准的战斗行动。星球当局已收到多份报告，称贵部队以虚假理由与一支看似持牌的独立安保承包商交战。即日起，在全面调查结束前，将对贵组织施加临时留置，金额为 40 亿 C 币。——高级专员哈琳·沃雷利。”</color><color=#BFBFBF>通讯结束，没有协商余地，也没有申诉渠道。达里乌斯低声吹了声口哨。</color>“这就是绕着弯子敲诈啊。”<color=#BFBFBF>法拉皱眉查看任务的战术数据。</color>“[[DM.Factions[faction_MinnesotaTribe],明尼苏达部落]]的整支部队都在执行彻底的假旗行动，连应答器、涂装，甚至机甲底盘编号都做了伪装。被人骗过去也不奇怪。”<color=#BFBFBF>苏米蕾靠在控制台旁。</color>“四十亿？这不是罚款，是夷平一座城市的报价。”<color=#BFBFBF>杨嗤笑一声。</color>“他们要的不是钱，是想吓得我们开口。”<color=#BFBFBF>时机绝非巧合。{TGT_SYSTEM.OwnerDef.ShortName}有人怀疑这场冲突不只是雇佣兵互相开火，却还不知道背后另有隐情，正急着弄清真相。但此事确实蹊跷。阿蕾尔应该早就通知过当地政府了。只有一个人知道答案：该联系阿蕾尔了。</color>
'@
    }

    if ($file -eq 'event_GhostsOfRetribution_GhostBearWatch_VoyageToTheVault.json' -and
        $value.StartsWith('<color=#BFBFBF>An encrypted packet arrives quickly after the call with Arelle ended')) {
        return @'
<color=#BFBFBF>与阿蕾尔通话结束后不久，一份加密数据包便送达了。里面有坐标、任务标记，以及一个让全体船员立刻议论起来的名字：[[DM.BaseDescriptionDefs[LoreMajestyMetals],尊荣金属制造公司]]。这又是一家大型企业，难道要重演维科尔公司的旧事？跃迁准备警报在<i>阿尔戈号</i>的走廊里回响，船员们聚到全息桌旁。杨神情警惕地俯身查看。</color>“杜尼安郡六号。那可不是什么边境前哨。<i>尊荣金属公司</i>是内星区最大的工业巨头之一，哪怕在边境也是如此。他们什么都造：机甲底盘、装甲板、武器框架，甚至大型大气循环设备。要是他们在那里藏了个金库，里面的东西不只是值钱，很可能还是尖端技术。”<color=#BFBFBF>法拉点开一份读数，皱起眉头。</color>“金库埋在他们一处较早的原型设施下方，与吉格斯威克郊外的<b>阿尔法环形工厂</b>相连。那是他们突击型机甲部门的研发基地。里面可能有武器蓝图，也可能有结构强化技术……但可以肯定，[[DM.Factions[faction_MinnesotaTribe],明尼苏达部落]]想要完整拿到里面的东西。”<color=#BFBFBF>苏米蕾扬起眉毛。</color>“等等，杜尼安郡的统治者知道我们要来吗？<i>杜尼安郡</i>可是他们的领地。尊荣金属公司自己的安保队又怎么办？要是他们看见我们的机甲朝一处黑站点走去，我们能确定他们不会开火吗？”<color=#BFBFBF>四周一片沉默，没人回答。大家互相看了看，达里乌斯耸耸肩。</color>“我们有坐标、授权标记，也有任务。只能相信阿蕾尔已经处理妥当了。”<color=#BFBFBF>苏米蕾低声嘀咕：</color>“没错，相信守望组织准没错。”<color=#BFBFBF>你点点头，决定已定。<i>阿尔戈号</i>锁定航向。尊荣金属公司的金库正在<i>杜尼安郡六号</i>等着你们，而无论里面藏着什么，明尼苏达部落已经开始行动。</color>
'@
    }

    if ($file -eq 'event_GhostsOfRetribution_MinnesotaTribe_FlaggedStars.json' -and
        $value -match '(?i)(Shortly after arriving in orbit over|短ly after arriving in orbit over)') {
        return @'
<color=#BFBFBF>抵达{TGT_SYSTEM.Name}轨道后不久，法拉便注意到一份通过水木在首次简报时提供的部落安全频道传来的新加密数据包。解密后，数据包展开成一张密集的星图：十三个星系散布在外缘腹地，各自标有部落内部代号。每一处都对应一个已知或休眠中的据点：偏远设施、资源储备点、备用避难所和研究前哨。这不是战场传闻，也不是打捞记录，而是真正的基础设施，代表着真实的势力范围。如今你们加入了他们一方，他们才把这些信息交给你的船员。另有一条记录格外醒目，似乎是根据你们自己的报告标注的。</color><color=#DFDFDF>“星系条目：MELIDRON——列为可能的幽灵熊守望组织占领目标。”</color><color=#BFBFBF>法拉快速浏览条目，同时把其余数据与跃迁坐标和威胁图层对齐。</color>“好……正在同步。来看看我们掌握了什么。”<color=#BFBFBF>你第一次看见部落真正疆域的边缘散布于星海之中，或者说，看见了他们愿意向新盟友透露的部分。这些不再是传闻，也不再是神话，而是一颗颗等待着人们为之而战的星球。</color>
'@
    }

    if ($file -eq 'event_co_BearingDown.json' -and
        $value.StartsWith('[[SCN_MW,{SCN_MW.Callsign}]] knocks on your open doorway')) {
        return @'
[[SCN_MW,{SCN_MW.Callsign}]]敲了敲你办公室敞开的门：“{Commander.FIRSTNAME} {Commander.LASTNAME} 指挥官，您现在方便谈谈吗？”直到今天，你仍不太习惯{SCN_MW.Det_C}夹杂着氏族方言的说话方式。“嗯，可以……请进。有什么事吗，机甲战士？”[[SCN_MW,{SCN_MW.Callsign}]]走到你桌前的空椅子旁坐下。{SCN_MW.Det}身形比常人高大不少，坐在椅子上显得有些局促。你不由得想到，虽然{SCN_MW.SUBJ}按元素战士的标准算是矮小，穿上动力装甲后却会十分强悍。[[SCN_MW,{SCN_MW.Callsign}]]打断了你的思绪，直视着你：“{Commander.FIRSTNAME} {Commander.LASTNAME} 指挥官，我正式请求您批准我离开{COMPANY.CompanyName}。”这番直白的话让你一愣：“什么？你是说想退出{COMPANY.CompanyName}？”“是的，{Commander.FIRSTNAME} {Commander.LASTNAME} 指挥官。”[[SCN_MW,{SCN_MW.Callsign}]]说道，“我作为星蝰氏族的一员，有一件必须完成的事，而且不能让公司卷入其中。”你长长地呼了口气：“我们当然可以送你去目的地。你要去哪里？”[[SCN_MW,{SCN_MW.Callsign}]]摇摇头：“不，{Commander.FIRSTNAME} {Commander.LASTNAME} 指挥官。谢谢您的好意，但这件事只有获得血名的星蝰氏族成员才能参与。若您批准我离队，等我完成任务后会联系您，再回来加入公司。”你看得出{SCN_MW.Subj}不打算再多说，但还是追问道：“能具体说说吗？”[[SCN_MW,{SCN_MW.Callsign}]]回答：“我在氏族中还有未了之事。完成任务后，我会脱胎换骨。我想用新的技能取代自己的一部分旧本领，就像蝰蛇蜕皮一样。您会批准我离开，对吧？”
'@
    }

    if ($file -eq 'event_co_KFCMajor.json' -and
        $value.StartsWith('Darius comes into your office and hands you a datapad')) {
        return @'
达里乌斯走进你的办公室，把一台数据板递给你：“指挥官，那次误跃迁损坏的电路板和其他部件，维修费用已经估算出来了。”你接过数据板，翻看上面的资料：“修好这些部件要花六百万到一千万 C 币？！”达里乌斯回答：“是的，长官。<i>阿尔戈号</i>的多个推进系统都严重受损，而且其中一些部件相当稀有，尤其考虑到我们目前所在的位置。”你把数据板扔到桌上：“如果我们决定不修呢？”达里乌斯捡起数据板，翻看了几条资料：“那在修好之前，我们已经为<i>阿尔戈号</i>安装的多个核心升级都无法使用。简单说，我们的航行能力会大幅下降，而且在修好控制台之前也无法使用海盗点数。”达里乌斯平静地等着你作出决定。
'@
    }

    if ($file -eq 'event_co_LastRites.json' -and
        $value.StartsWith('You take the datapad from [[SCN_MW,{SCN_MW.Callsign}]]')) {
        return @'
你接过[[SCN_MW,{SCN_MW.Callsign}]]递来的数据板：“先给我讲讲重点，这样我之后再仔细看时就能明白了。”[[SCN_MW,{SCN_MW.Callsign}]]笑着点头：“是，指挥官。简单来说，要重建我的<i>Minsk</i>，最省事的办法就是从各自的工厂取得原厂零件。跑这些星系一趟所花的时间，可以由直接在一台<i>Minsk MNK-102</i>供体底盘上组装整机省下来。”你点点头，表示目前都听得明白：“请继续。”[[SCN_MW,{SCN_MW.Callsign}]]接着讲述{SCN_MW.Det}的计划：“我们需要前往以下星系：<color=#FFBF00><i>新地岛，取得三个部件；伽拉忒亚，取得三个部件；维帕瓦，取得两个部件；拉德施塔特、吉布斯和弗莱彻，各取得一个部件。</i></color>其余部件都是<i>Minsk MNK-102</i>的标准配置。”你琢磨了一下：“你刚才说要去七个星系，可我数出来只有六个？”[[SCN_MW,{SCN_MW.Callsign}]]再次点头：“是的，指挥官。最后一站是拉萨尔哈格。那里有一处设施，可以把所有零件组装起来，重建<i>Last Rites</i>。”你拍了拍手中的数据板：“相关信息都在这里了吧？需要哪些东西、怎么取得之类的都有？我可不想等到最后才发现，我们要偷袭或抢劫一处根本无法全身而退的设施。”[[SCN_MW,{SCN_MW.Callsign}]]挺直身子，郑重地说：“指挥官，以我作为<i>幽灵熊自治领</i>氏族人的荣誉担保，计划中的一切都合法合规。”你笑了笑：“谢谢你，机甲战士。我会和指挥部其他成员一起研究这份计划，再决定如何处理你的请求。接下来肯定会有一连串有意思的事；而且，考虑到你驾驶<i>Last Rites</i>立下的战绩，{COMPANY.CompanyName}今后还能接到报酬更丰厚的合约！”<b><color=#15df37>星系名称已添加至指挥官的能力弹出面板</color></b>
'@
    }

    if ($file -eq 'event_co_LastRitesPostpone.json' -and
        $value -match '^\s*"?Tell you what, join me while I get some chow') {
        return @'
“这样吧，陪我去吃点东西。你可以先讲讲这份数据板上的重点，这样我之后再仔细看时就能明白了。”[[SCN_MW,{SCN_MW.Callsign}]]笑着点头：“是，指挥官。简单来说，要重建我的<i>Minsk</i>，最省事的办法就是从各自的工厂取得原厂零件。跑这些星系一趟所花的时间，可以由直接在一台<i>Minsk MNK-102</i>供体底盘上组装整机省下来。”你点点头，表示目前都听得明白：“请继续。”[[SCN_MW,{SCN_MW.Callsign}]]接着讲述{SCN_MW.Det}的计划：“我们需要前往以下星系：<color=#FFBF00><i>新地岛，取得三个部件；伽拉忒亚，取得三个部件；维帕瓦，取得两个部件；拉德施塔特、吉布斯和弗莱彻，各取得一个部件。</i></color>其余部件都是<i>Minsk MNK-102</i>的标准配置。”你琢磨了一下：“你刚才说要去七个星系，可我数出来只有六个？”[[SCN_MW,{SCN_MW.Callsign}]]再次点头：“是的，指挥官。最后一站是拉萨尔哈格。那里有一处设施，可以把所有零件组装起来，重建<i>Last Rites</i>。”你拍了拍手中的数据板：“相关信息都在这里了吧？需要哪些东西、怎么取得之类的都有？我可不想等到最后才发现，我们要偷袭或抢劫一处根本无法全身而退的设施。”[[SCN_MW,{SCN_MW.Callsign}]]挺直身子，郑重地说：“指挥官，以我作为<i>幽灵熊自治领</i>氏族人的荣誉担保，计划中的一切都合法合规。”
'@
    }

    if ($file -eq 'event_mw_KrakenGoodRigger.json' -and
        $value.StartsWith('You are on the bridge when Sumire calls out')) {
        return @'
你正在舰桥上，苏米蕾喊道：“指挥官，有一段全息影像通讯呼入。”你示意苏米蕾接通通讯：“{COMMANDER.LastName} 指挥官，您好。您和{COMPANY.CompanyName}近来可好？一切都还顺利吧？”你抱起双臂：“你还真是阴魂不散。这次又是谁欠了你的钱，<i>幕后主使</i>？”<i>幕后主使</i>笑了笑，没有回答：“你可真聪明。我花了些时间才看清你的盘算，不过现在我知道你在做什么了。”你靠回椅子：“那你倒说说，我在做什么？”<i>幕后主使</i>拿出数据板，滑动着上面的记录：“亲爱的指挥官，你在自己人里安排了内应，让你的<i>参赛者</i>一路闯过所有挑战，从而替你们公司拿下冠军奖金。”你摆出最沉着的表情，思索片刻后答道：“我为什么要这么做？我手上有什么资源，能让你的人故意睁一只眼闭一只眼？而且，我还要抗议……”<i>幕后主使</i>打断了你的话：“得了吧，指挥官。记录显示，{COMPANY.CompanyName}已经有五名以上的冠军。你知道出现五名冠军的概率有多低吗？按我的计算，这些人的奖金加起来，足以收买我的某个手下，让他对此视而不见。”你冷冷地盯着<i>幕后主使</i>：“你经营的那场‘比赛’分明就是让参赛者送命，居然还敢指责我操纵比赛？你真是个伪君子。”<i>幕后主使</i>阴险地笑了：“即便如此，归根结底，比赛由我说了算，我想怎么安排就怎么安排。你没有义务雇用得罪过<i>辛迪加</i>的罪犯。说到这里，我正是为此联系你：辛迪加要求你为故意确保参赛者获胜的行为作出赔偿。为了证明我们是认真的，我们已经把你的冠军之一[[TGT_MW,{TGT_MW.Callsign}]]扣在了[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]地表。”<i>全息屏幕上出现了{TGT_MW.Callsign}被绑住并堵住嘴的画面。</i>“你要是不肯付钱，谁知道他们会遭遇什么？看在我们还有商量余地的份上，只收你 7,500,000 C 币。我劝你慎重选择，指挥官。”达里乌斯凑过来低声说道：“指挥官，我查过记录，[[TGT_MW,{TGT_MW.Callsign}]]确实下地表休假去了。他们说不定真的抓到了{TGT_MW.OBJ}。”
'@
    }

    if ($file -eq 'event_mw_Bagele_Stash.json' -and
        $value.StartsWith('You look at [[TGT_MW,{TGT_MW.Callsign}]]. "What''s in this pod?"')) {
        return @'
你看向[[TGT_MW,{TGT_MW.Callsign}]]：“这舱里装的是什么？”Bagele皱起眉头，俯身查看传感器读数。“说实话，指挥官，我也和你一样不知道。我从不问客户把什么东西藏起来，也不打算现在才问。”达里乌斯开始皱眉，翻查传感器读数。“指挥官，我不确定该怎么判断。传感器检测到的可能是一具休眠的聚变核心，也可能完全是别的东西。舱体看起来没有危险，但我建议在外面打开，以防万一。”Bagele点头赞同：“这大概是最稳妥的做法。我的客户把东西藏在荒无人烟的地方自有理由。它可能没问题，但我可不想拿这个打赌。”<i>阿尔戈号</i>后撤到安全距离，补给舱独自在太空中漂浮。Bagele穿上舱外活动服，小心翼翼地靠近；舰桥船员则通过外部摄像头观察。“没有明显损伤，”Bagele汇报，“能源读数很低，里面的东西已经休眠很久了。”检查几分钟后，Bagele找到了主要舱门机构。“看起来是标准的安全锁。藏东西的人没料到会有专业打捞队来。”锁扣发出金属撞响，舱门缓缓展开。Bagele头盔上的摄像灯照亮舱内：“指挥官……您最好亲自看看。”画面拉近。小小的舱体里塞满了各类物资：弹药、生命维持模块、助推器。达里乌斯立刻坐直身体：“这不是随便装的货物，是一处小型储藏点。”Bagele点点头：“看起来像海盗的储藏点。有人把一批备用物资埋在了这里。”“能查出是谁的吗？”你问。“暂时不行，”Bagele回答，“大部分标记都被刻意抹掉了。但这些肯定是海盗的货。”达里乌斯开始查看库存画面：“在这种荒郊野外捡到一只漂流舱，收获还不错。”回收人员开始靠近，库存扫描也随之启动。自发现这只舱体以来，这个谜团总算可能带来实际收获了。
'@
    }

    if ($file -eq 'event_co_KrakenMRBC.json' -and
        $value.StartsWith('You are on the bridge when Sumire calls out, "Commander, there is a Priority Alpha holocom alert')) {
        return @'
你正在舰桥上，苏米蕾喊道：“指挥官，您有一条最高优先级的全息通讯警报，标注为机密。”

你起身离开舰桥：“转到我办公室，苏米蕾。”

你进入办公室，全息通讯器上的红灯正在闪烁。你坐下并输入个人密码：<color=#FFFF00><i>D4R1U5_15_4N_ID10T</i></color>。设备启动，雇佣兵评审与担保委员会的徽记在你面前旋转，随后屏幕亮起<color=#FF0000><i>安全连接已建立</i></color>。

徽记淡去，画面上出现一位衣着考究的长者。“{COMMANDER.LastName} 指挥官，您好。我是乔鲁斯·塞瓦尔，担任多家在 MRBC 注册的雇佣兵公司的法律顾问。我也是<i>{COMPANY.CompanyName}</i>的指定顾问，负责确保各项合同得到妥善合法履行，并处理针对我所负责公司的投诉和其他违规问题。我们此前没有正式见过面，这并不罕见。不过，请您先进行视网膜扫描，以确认您是{COMMANDER.LastName}指挥官。”

你面露疑惑，但还是决定配合，看看他究竟想做什么。你向前倾身，让摄像头扫描眼睛。

塞瓦尔查看终端上的信息后说道：“谢谢您，{COMMANDER.LastName} 指挥官。现在可以谈谈事情的来龙去脉了。至少有五位民众联系了 MRBC，其中包括[[DEAD_MW,{DEAD_MW.FirstName}]] <i>[[DEAD_MW,{DEAD_MW.Callsign}]]</i> [[DEAD_MW,{DEAD_MW.LastName}]]。他们都称有亲属最后受雇于贵公司，如今下落不明。您能说明一下情况吗？”

你在椅子上坐直：“塞瓦尔先生，我们是一家承接各类任务的雇佣兵公司，而这些工作对参与者来说都可能致命。那些失踪人员很可能已在战斗中阵亡。”

塞瓦尔看了看终端，随后转向你：“指挥官，我不是陪审员，也不是法官。我是来协助您的，但要做到这一点，我需要知道发生了什么。MRBC 的记录显示，您雇用了所有这些人；他们的账户里至少收到过一笔来自<i>{COMPANY.CompanyName}</i>的薪金。但记录中没有证据表明这些机师已被申报为阵亡。您也清楚，《第四章 C 项第七款》列出了机师阵亡或在战斗中失踪时必须办理的手续。贵公司没有提交任何相关文件。”

你打开办公桌，拿出船员名册，快速翻看曾受雇于<i>{COMPANY.CompanyName}</i>的机师名单。上面都记录了他们离开公司的时间、地点和原因，唯独现役人员以及几名因<i>幕后主使</i>而离开公司的船员没有完整档案。你清了清嗓子，对塞瓦尔说道：“呃，看来……如果我的记录不完整，会有什么后果？”

塞瓦尔看着终端念道：“MRBC 第 264 号准则规定：<i><color=#D4AF37>经任何 MRB 招募大厅雇用的雇佣兵公司机甲战士及其他人员，只要其身份状态发生变化，公司就必须向 MRBC 提交更新后的记录。未提交有效更新，可能会被处以最高 ¢3,500,000 的罚款，和／或声望处罚，使评级降至 300 以下。</color></i>

这意味着，如果您无法证明他们仍然在世——也就是说，MRBC 必须能够实际联系到他们——贵公司和雇佣兵执照都可能受到严厉制裁。如果您知道他们的遭遇，请告诉我，我会转达给 MRBC。主动协助调查，或许能让他们从宽处理。”
'@
    }

    if ($file -eq 'event_co_KrakenMRBC.json' -and
        $value -match '^\s*["“”]?So, if I cannot provide the current whereabouts of my former crew') {
        if ($value -match 'You mull over y(?:ou|our) options before blurting out') {
            $fine = [regex]::Match($value, 'fined the amount of ¢(?<fine>[\d,]+)').Groups['fine'].Value
            $rating = [regex]::Match($value, 'Rating will be reset to (?<rating>\d+)').Groups['rating'].Value
            if (-not $fine -or -not $rating) { return $null }
            $translated = @'
“如果我无法提供前船员现在的下落，MRBC会找我麻烦？”你问塞瓦尔先生。

塞瓦尔平静地回答：“事情不是这样的，指挥官。雇佣兵公司有义务申报在战斗中阵亡的机甲战士和其他船员，以便他们登记在 MRBC 的家属或受益人领取遗物，也能申请他们生前购买的保险金。未申报死亡，实际上等于剥夺了他们亲属应得的权益。”

你斟酌片刻，脱口而出：“<i>幕后主使</i>。那些失踪船员和<i>幕后主使</i>有关。”

塞瓦尔看了你一会儿：“<i>幕后主使</i>是谁？更重要的是，他和这件事有什么关系？”

接下来的一小时里，你把辛迪加、<i>幕后主使</i>以及他让部分船员参加的比赛从头到尾讲了一遍。你尽力向塞瓦尔说明，每位船员都是自愿参赛，想借此还清欠辛迪加的债务。

塞瓦尔一边记录一边认真听完了全部细节。把你的陈述录入数据库后，他抬头说道：“我已经把您说的一切转达给上级了。现在只能等消息。”

大约二十分钟后，塞瓦尔的终端响起提示音。他看完信息后说道：“{COMMANDER.LastName} 指挥官，MRBC似乎相信了您的说法。他们也听说过您提到的辛迪加。”

你松了口气：“那就好。至少这件事可以告一段落，公司也能恢复正常工作了。”

你伸手准备结束通讯，塞瓦尔却打断了你：“先别急，指挥官。您确实可以不再为前船员的死讯负责，但仍然违反了 MRB 准则。您至少没有为五名船员向 MRBC 提交状态变更表。如果在此类情况下处以最高处罚，可能累计罚款 ¢25,000,000，MRB 评级还会降至零。”

你跌回椅子里，张口结舌，说不出话来。塞瓦尔继续说道：“不过，您愿意配合 MRBC 解决问题，因此委员会决定从宽处理。现裁定对<i>{COMPANY.CompanyName}</i>处以 ¢__FINE__ 罚款，并将 MRB 评级重置为 __RATING__。请用拇指签署这份宣誓书，我就不再打扰您了。”

你浑身发麻，茫然地把拇指按上扫描器。几秒后，设备发出提示音。塞瓦尔什么时候结束通讯的，你都没有留意，只顾沉浸在这一切的来龙去脉中。
'@
            return $translated.Replace('__FINE__', $fine).Replace('__RATING__', $rating)
        }

        if ($value -match 'You calmly address Mr\. Sevar' -and $value -notmatch 'deposit ¢7,500,000') {
            $fine = [regex]::Match($value, 'fined the amount of ¢(?<fine>[\d,]+)').Groups['fine'].Value
            $rating = [regex]::Match($value, 'Rating will be reset to (?<rating>\d+)').Groups['rating'].Value
            if (-not $fine -or -not $rating) { return $null }
            $translated = @'
“如果我无法提供前船员现在的下落，MRBC会找我麻烦？”你问塞瓦尔先生。

塞瓦尔平静地回答：“事情不是这样的，指挥官。雇佣兵公司有义务申报在战斗中阵亡的机甲战士和其他船员，以便他们登记在 MRBC 的家属或受益人领取遗物，也能申请他们生前购买的保险金。未申报死亡，实际上等于剥夺了他们亲属应得的权益。”

你平静地对塞瓦尔说道：“经营一家雇佣兵公司并不容易。那些失踪人员现在在哪里，我确实无从回答。没错，他们曾受雇于我们，我们也确实没有提交离职文件。但请理解，这不是有意怠慢；我们不知道这是合同规定。我们过去从未和 MRBC 出过问题，能否从轻处理？”

塞瓦尔认真听完你解释为何没有遵守流程，随后在终端上输入一连串信息，再转向你：“我已经把您说的一切转达给上级了。现在只能等消息。”

大约二十分钟后，塞瓦尔的终端响起提示音。他看完信息后说道：“{COMMANDER.LastName} 指挥官，考虑到这是贵公司第一次违反 MRBC 政策，委员会愿意从宽处理。”

你松了口气：“那就好。我保证以后会及时更新所有文件。至少这件事可以告一段落，公司也能恢复正常工作了。”

你伸手准备结束通讯，塞瓦尔却打断了你：“不过还有一件事需要处理，指挥官。MRBC虽然决定不追究您前船员的下落，但贵公司仍未遵守 MRB 准则。您至少没有为五名船员向 MRBC 提交状态变更表。如果在此类情况下处以最高处罚，可能累计罚款 ¢25,000,000，MRB 评级还会降至零。”

你跌回椅子里，张口结舌，说不出话来。塞瓦尔接着说道：“不过，正如您所说，贵公司过去从未违反合同或政策，因此 MRBC 决定免除其余违规事项，只保留一项。现裁定对<i>{COMPANY.CompanyName}</i>处以 ¢__FINE__ 罚款，并将 MRB 评级重置为 __RATING__。请用拇指签署这份宣誓书，我就不再打扰您了。”

你浑身发麻，茫然地把拇指按上扫描器。几秒后，设备发出提示音。塞瓦尔什么时候结束通讯的，你都没有留意，只顾沉浸在这一切的来龙去脉中。
'@
            return $translated.Replace('__FINE__', $fine).Replace('__RATING__', $rating)
        }

        if ($value -match 'deposit ¢7,500,000 into an account nominated by you') {
            return @'
“如果我无法提供前船员现在的下落，MRBC会找我麻烦？”你问塞瓦尔先生。

塞瓦尔平静地回答：“事情不是这样的，指挥官。雇佣兵公司有义务申报在战斗中阵亡的机甲战士和其他船员，以便他们登记在 MRBC 的家属或受益人领取遗物，也能申请他们生前购买的保险金。未申报死亡，实际上等于剥夺了他们亲属应得的权益。”

你平静地对塞瓦尔说道：“经营一家雇佣兵公司并不容易。那些失踪人员现在在哪里，我确实无从回答。没错，他们曾受雇于我们，我们也确实没有提交离职文件。但请理解，这不是有意怠慢；我们不知道这是合同规定。我们过去从未和 MRBC 出过问题，能否从轻处理？”

塞瓦尔认真听完你解释为何没有遵守流程，随后在终端上输入一连串信息，再转向你：“我已经把您说的一切转达给上级了。现在只能等消息。”

大约二十分钟后，塞瓦尔的终端响起提示音。他看完信息后说道：“{COMMANDER.LastName} 指挥官，考虑到这是贵公司第一次违反 MRBC 政策，委员会愿意从宽处理。”

你松了口气：“那就好。至少这件事可以告一段落，公司也能恢复正常工作了。”

你伸手准备结束通讯，塞瓦尔却打断了你：“先别急，指挥官。贵公司仍然违反了 MRB 准则。您至少没有为五名船员向 MRBC 提交状态变更表。如果在此类情况下处以最高处罚，可能累计罚款 ¢25,000,000，MRB 评级还会降至零。”

你跌回椅子里，张口结舌，说不出话来。听到这里，你微笑着回答：“塞瓦尔先生，我明白真正的问题是什么了。如果我往您指定的账户汇入 ¢7,500,000，让您……<i>‘偿还那些家庭’</i>，您看如何？”

塞瓦尔露出狡黠的笑容：“亲爱的指挥官，您真是太慷慨了。既然贵公司过去从未违反合同或政策，我会确保 MRBC 免除所有违规处罚。请用拇指签署这份宣誓书，授权转账 ¢7,500,000，我就不再打扰您了。”

你把拇指按上扫描器。几秒后，设备发出提示音，确认转账成功。
'@
        }
    }

    return $null
}

function Translate-VisibleEventTerms([string]$rel, [string]$value) {
    $file = [IO.Path]::GetFileName($rel)
    $isEventText = $rel -match '(?i)(?:^|[\\/])events[\\/]|(?:^|[\\/])(?:force?d?event|event)[^\\/]*\.json$'

    if ($isEventText) {
        $rules = @(
            @{ Pattern='(?i)(?<![A-Za-z])Front Man(?![A-Za-z])'; Replacement='首脑' },
            @{ Pattern='(?i)(?<![A-Za-z])前(?:方|部) Man(?![A-Za-z])'; Replacement='首脑' },
            @{ Pattern='(?i)(?<![A-Za-z])Darius Oliveira(?![A-Za-z])'; Replacement='达吕斯·奥利维拉' },
            @{ Pattern='(?i)(?<![A-Za-z])Dr\.?\s+Murad(?![A-Za-z])'; Replacement='穆拉德博士' },
            @{ Pattern='(?i)(?<![A-Za-z])Darius''s(?![A-Za-z])'; Replacement='达吕斯的' },
            @{ Pattern='(?i)(?<![A-Za-z])Dairus''s(?![A-Za-z])'; Replacement='达吕斯的' },
            @{ Pattern='(?i)(?<![A-Za-z])Sumire''s(?![A-Za-z])'; Replacement='苏米尔的' },
            @{ Pattern='(?i)(?<![A-Za-z])Yang''s(?![A-Za-z])'; Replacement='杨的' },
            @{ Pattern='(?i)(?<![A-Za-z])Murad''s(?![A-Za-z])'; Replacement='穆拉德的' },
            @{ Pattern='(?i)(?<![A-Za-z])Farah''s(?![A-Za-z])'; Replacement='法拉的' },
            @{ Pattern='(?i)(?<![A-Za-z])Leopard''s(?![A-Za-z])'; Replacement='豹式空投艇的' },
            @{ Pattern='(?i)(?<![A-Za-z])Argo''s(?![A-Za-z])'; Replacement='阿尔戈号的' },
            @{ Pattern='(?i)(?<![A-Za-z])Darius(?![A-Za-z])'; Replacement='达吕斯' },
            @{ Pattern='(?i)(?<![A-Za-z])Dairus(?![A-Za-z])'; Replacement='达吕斯' },
            @{ Pattern='(?i)(?<![A-Za-z])Sumire(?![A-Za-z])'; Replacement='苏米尔' },
            @{ Pattern='(?i)(?<![A-Za-z])Yang(?![A-Za-z])'; Replacement='杨' },
            @{ Pattern='(?i)(?<![A-Za-z])Murad(?![A-Za-z])'; Replacement='穆拉德' },
            @{ Pattern='(?i)(?<![A-Za-z])Farah(?![A-Za-z])'; Replacement='法拉' },
            @{ Pattern='(?i)(?<![A-Za-z])Leopard(?![A-Za-z])'; Replacement='豹式空投艇' },
            @{ Pattern='(?i)(?<![A-Za-z])Argo(?![A-Za-z])'; Replacement='阿尔戈号' },
            @{ Pattern='(?i)(?<![A-Za-z])The Steel Beast(?![A-Za-z])'; Replacement='钢铁野兽' },
            @{ Pattern='(?i)(?<![A-Za-z])The Raptors(?![A-Za-z])'; Replacement='猛禽组织' },
            @{ Pattern='(?i)(?<![A-Za-z])Rogue Bear(?![A-Za-z])'; Replacement='流浪熊' },
            @{ Pattern='(?i)(?<![A-Za-z])PropWash was here(?![A-Za-z])'; Replacement='PropWash 到此一游' },
            @{ Pattern='(?i)(?<![A-Za-z])Wicced FTW(?![A-Za-z])'; Replacement='Wicced 必胜' }
        )
        foreach ($rule in $rules) {
            $value = [regex]::Replace($value, $rule.Pattern, $rule.Replacement)
        }
    }

    if ($rel -match '(?i)(?:^|[\\/])NecromoNightmare[\\/]events[\\/]event_co_Boneyard\.json$') {
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])TRICK(?![A-Za-z])', '恶作剧')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])TREAT(?![A-Za-z])', '款待')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])OR(?![A-Za-z])', '还是')
    }

    if ($rel -match '(?i)(?:^|[\\/])OperationRevival[\\/]Events[\\/]') {
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])Participate\s+in\s+实弹\s+Exercise(?![A-Za-z])', '参加实弹演习')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])Travel\s+Contract\s+to\s+诺瓦ya\s+Zemlya(?![A-Za-z])', '前往新地岛的旅行合约')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])诺瓦ya\s+Zemlya(?![A-Za-z])', '新地岛')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])Novaya\s+Zemlya(?![A-Za-z])', '新地岛')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])NovayaZemlya(?![A-Za-z])', '新地岛')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])Bergan Industries(?![A-Za-z])', '贝根工业')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])Last Rites(?![A-Za-z])', '临终仪式')
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])Khaos Theory(?![A-Za-z])', '混沌理论')
    }

    if ($rel -match '(?i)(?:^|[\\/])Aircademy[\\/]events[\\/]') {
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])Air Today, Gone Tomorrow(?![A-Za-z])', '今日翱翔，明日消逝')
    }
    if ($file -eq 'LoreTheMuscle.json') {
        $value = [regex]::Replace($value, '(?i)(?<![A-Za-z])The Muscle(?![A-Za-z])', '主力')
    }

    if ($file -eq 'event_solarisSeasonStart4.json') {
        $value = [regex]::Replace($value, '(?i)Purchase\s+access\s+to\s+a\s+索拉里斯\s*7号\s+冠军ship', '购买索拉里斯7号锦标赛的参赛资格')
    }
    if ($file -match '^event_sh_gate\d+_assessment\.json$') {
        $value = $value.Replace('超重型合约（Superheavy Contracts）', '超重型合约')
    }
    if ($file -eq 'forcedevent_co_KhaosTheory_Search.json') {
        $value = [regex]::Replace($value, '(?i)Look for the\s*$', '寻找')
    }
    if ($file -eq 'fp_NN.json' -and $value -eq '测试 Kickstart NN') {
        $value = '死灵噩梦启动测试'
    }
    if ($file -eq 'SimGameStatDesc_ConsoleBuilt.json') {
        $value = [regex]::Replace($value, '(?i)^Stat f或 KF Console Built on 阿尔戈号$', '阿尔戈号上 KF 控制台的建造统计')
    }
    if ($file -eq 'SimGameStatDesc_ConsoleDelayed.json') {
        $value = [regex]::Replace($value, '(?i)^Stat f或 KF Console Delayed on 阿尔戈号$', '阿尔戈号上 KF 控制台的延期统计')
    }

    return $value
}

function Translate-EventTerms([string]$rel, [string]$value) {
    $file = [IO.Path]::GetFileName($rel)
    $originalValue = $value
    if ($value -eq 'NYI') { return '尚未实现' }
    if ($value -eq 'Ensure VIP survives') { return '确保重要人物存活' }
    if ($value -eq 'Rescue the VIP and extract safely') { return '救出重要人物并安全撤离' }
    if ($value -eq 'Rescue the VIP from the {TEAM_TAR.FactionDef.Demonym} base.') { return '从{TEAM_TAR.FactionDef.Demonym}基地救出重要人物。' }
    if ($value -eq "Recover the VIP's briefcase.") { return '取回重要人物的公文包。' }
    if ($value -eq '一旦你掌握了VIP，就带她前往指定的着陆区撤离。') { return '救出重要人物后，带她前往指定着陆区撤离。' }
    if ($value -eq 'VIP 已救出，指挥官。干得漂亮。') { return '重要人物已安全救出，指挥官。干得漂亮。' }
    if ($value -eq 'VIP 已被救到安全地点，指挥官。任务完成。') { return '重要人物已安全撤离，指挥官。任务完成。' }
    if ($value -eq 'VIP安全了，指挥官--做得不错。') { return '重要人物已安全，指挥官——做得不错。' }
    if ($value -eq '占领指定区域来回收VIP.' -or $value -eq '占领指定区域来回收VIP') { return '占领指定区域以救出重要人物。' }
    if ($value -eq '占领次要指定区域来回收VIP的助手' -or $value -eq '占领次要指定区域来回收VIP的助手.') { return '占领次要指定区域，救出重要人物的助手。' }
    if ($value -eq '回收VIP并摆脱敌人') { return '救出重要人物并摆脱敌人。' }
    if ($value -eq '回收VIP并安全撤离') { return '救出重要人物并安全撤离。' }
    if ($value -eq '载有VIP的机甲必须存活') { return '载有重要人物的机甲必须存活。' }
    if ($value -eq '载有VIP助手的机甲必须存活') { return '载有重要人物助手的机甲必须存活。' }
    if ($value -eq '拿下B区以回收VIP的助手') { return '占领B区，救出重要人物的助手。' }
    if ($value -match '^ENEMYFACTION 那些渣滓正试图从一处转移到另一处。干掉他们。$') {
        return '{TEAM_TAR.FactionDef.Demonym}的杂碎正试图转移。干掉他们。'
    }
    if ($value -match '^The ENEMYFACTION scum are trying to get from one place to another\. Kill them\.$') {
        return '{TEAM_TAR.FactionDef.Demonym}的杂碎正试图转移。干掉他们。'
    }
    if ($file -eq 'DefendBase_Bodyguards.json' -and $value.StartsWith('我们在{TGT_SYSTEM.name}')) {
        return '我们在{TGT_SYSTEM.name}的一处基地有位重要人物。当地特工刚发来一条含糊的消息，称{TEAM_TAR.FactionDef.Name}即将袭击基地，目标正是这位重要人物；对方还知道我们的部队无法及时赶到支援。我们需要一支可靠的雇佣兵小队保护基地和人员。'
    }
    if ($file -eq 'DefendBase_Bodyguards.json' -and $value.StartsWith('他们一定很后悔让他们的VIP')) {
        return '他们一定很后悔让重要人物在没有加强安保的情况下外出。不过，他们犯下的错误正是我们赚钱的机会。'
    }
    if ($file -eq 'GoR_MinnesotaTribe_AmbushConvoy_BrokenChains.json' -and $value.StartsWith('有几艘运输车')) {
        return '车队中有几辆运输车，但载着蒂尔赛博士的是一辆伪装车辆。车尾设有加固收容舱，即使车辆被摧毁也能保护她；那部分几乎能承受任何攻击。摧毁车辆后，我们就能把她救出来。'
    }
    if ($file -eq 'GoR_MinnesotaTribe_AmbushConvoy_BrokenChains.json' -and $value.StartsWith('强化 VIP 舱撑住了')) {
        return '加固收容舱撑住了攻击。我已锁定蒂尔赛博士的生命信号，她还活着。'
    }

    $protected = [regex]::new('<[^>]*>|\[\[.*?\]\]|\{[^{}]*\}')
    $vipRx = [regex]::new('(?<![A-Za-z])VIP(?:''s|s)?(?![A-Za-z])', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $enemyRx = [regex]::new('(?<![A-Za-z])ENEMYFACTION(?![A-Za-z])', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $out = New-Object Text.StringBuilder
    $last = 0
    foreach ($match in $protected.Matches($value)) {
        $visible = $value.Substring($last, $match.Index - $last)
        $visible = Translate-VisibleEventTerms $rel $visible
        $visible = $enemyRx.Replace($visible, '{TEAM_TAR.FactionDef.Demonym}')
        $visible = $vipRx.Replace($visible, [Text.RegularExpressions.MatchEvaluator]{
            param($m)
            if ($m.Value.EndsWith("'s", [StringComparison]::OrdinalIgnoreCase)) { return '重要人物的' }
            return '重要人物'
        })
        [void]$out.Append($visible)
        [void]$out.Append($match.Value)
        $last = $match.Index + $match.Length
    }
    $visible = $value.Substring($last)
    $visible = Translate-VisibleEventTerms $rel $visible
    $visible = $enemyRx.Replace($visible, '{TEAM_TAR.FactionDef.Demonym}')
    $visible = $vipRx.Replace($visible, [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        if ($m.Value.EndsWith("'s", [StringComparison]::OrdinalIgnoreCase)) { return '重要人物的' }
        return '重要人物'
    })
    [void]$out.Append($visible)
    $translated = $out.ToString()
    $translated = [regex]::Replace($translated, '(?<=[\u4e00-\u9fff])\s+(?=重要人物)|(?<=重要人物)\s+(?=[\u4e00-\u9fff])', '')
    if ($translated -eq $originalValue) { return $null }
    return $translated
}

function Translate-JsonDetails([string]$rel, [string]$value) {
    $eventGapTranslation = Translate-EventGap $rel $value
    if ($null -ne $eventGapTranslation) { $value = $eventGapTranslation }
    $eventTermTranslation = Translate-EventTerms $rel $value
    if ($null -ne $eventTermTranslation) { return $eventTermTranslation }
    if ($null -ne $eventGapTranslation) { return $eventGapTranslation }
    if ($rel -like '*Ammo_AmmunitionBox_Thunderbolt_20_NEMP.json' -and
        ($value.StartsWith('This Thunderbolt Missile') -or $value.StartsWith('This 雷霆导弹'))) {
        return @'
这枚雷霆导弹经过改装，可发射一种特殊的 NEMP 战斗部，在爆炸点周围瘫痪一切设备。NEMP 战斗部设计为在地表上空引爆。爆炸会释放伽马射线脉冲，扰乱电子设备。

<b><color=#00ffff>Ctrl+点击弹药计数器以抛弃弹药。</color></b>
'@
    }
    if ($rel -like '*Unique_Gear_Armor_MAD.json' -and
        ($value.StartsWith("This peculiar Marauder's") -or $value.StartsWith('这台特立独行的掠夺者'))) {
        return @'
这台特立独行的掠夺者机甲换装了 LAM 常用的超轻型 LAM 铝制装甲。由于异常的设计和'''LAM'''改造，掠夺者底盘失去了重新换装其他装甲的能力。<b><color=#0066ff>占用 2 个槽位</color></b>
'@
    }
    if ($rel -like '*Weapon_Artillery_ArrowIV_Pirate.json' -and
        ($value.StartsWith('You really should') -or $value.StartsWith('老板，你真该'))) {
        return @'
老板，你真该停止购买这些便宜货了！废气会直接排入你的机甲，而它的防护外壳已经被彻底拆除！

<b><color=#ffcc00>使用箭 IV 弹药。</color></b>
'@
    }
    if ($rel -like '*event_GhostsOfRetribution_GhostBearWatch_CurtainFall.json' -and
        $value.StartsWith('<color=#BFBFBF>A soft hum')) {
        return @'
<color=#BFBFBF>阿戈号舰桥里回荡着轻微嗡鸣，银河指挥官古尔德尔的通讯逐渐化为静电。没有后续，也没有结局。

只有寂静。

船员们陷入不安的沉思。守望者合约不再，战斗命令也不再。<i>末日</i>原型机消失了，阿蕾尔也一样。

没有消息，没有信号，没有踪迹。

在虚空某处，“Mizuki Bekker”仍在注视着一切，她的话语如幽灵般回荡：</color> <color=#DFDFDF>“你或许能阻止它，但你阻止不了其他人。”</color>

<color=#BFBFBF>但是，“其他人”究竟是谁，又究竟是什么？

如果部落失去了最强大的武器……他们接下来究竟会策划什么？

在深层边疆，曾经遍布部落活动的星系纷纷沉寂。没有袭击，没有通讯，只有寂静。

太安静了。你知道他们仍在那里，正在准备着什么。

当<i>阿戈</i>号缓慢驶回文明空间，舰上每个人心中都萦绕着一个问题：

这是一场胜利……还是仅仅拉开了序幕？

阿蕾尔·约根松究竟发生了什么？

Mizuki Bekker 的下一步是什么？

明尼苏达部落真的已经支离破碎，还是只是在为更糟糕的事情重新集结？

这一切真的结束了吗？</color>
'@
    }
    if ($rel -like '*event_GhostsOfRetribution_MinnesotaTribe_PayDay.json' -and
        $value.StartsWith('<color=#BFBFBF>A [[DM.Factions')) {
        return @'
<color=#BFBFBF>战斗结束三天后，一艘[[DM.Factions[faction_MinnesotaTribe],明尼苏达部落]]运输船抵达<i>阿戈</i>号。运输船毫无仪式感地完成对接，在达吕斯监督下开始卸货。</color>

<color=#BFBFBF>第一批货物是资金：两千万 C-币直接转入连队账户。达吕斯看着数据板上的到账确认，甚至不得不核对两遍交易记录才敢相信。</color>

“指挥官，马库斯没有夸大报酬。两千万 C-币刚刚打进我们的账户。这比我们完成六份合约赚到的总和还多。”

<color=#BFBFBF>杨在机甲库里看着第二批货物。一台明尼苏达部落突击机甲靠自身动力驶下运输船，部落技师交付认证代码和技术文档后便一言不发地离开。</color>

“老板，你真的得来看看。马库斯送了我们一台突击机甲，一台部落突击机甲。这东西完美得不像话。”

<color=#BFBFBF>接下来送达的是武器包。四个箱子上都盖着明尼苏达部落的安全封条，其中三个装着先进武器系统，杨打开时都忍不住停下来仔细端详。第四个箱子里有十二个大型弹药箱，足够让其中一件武器进行长时间作战。这是内圈难以接触到的部落军事科技。</color>

<color=#BFBFBF>最后送达的是专业设备。三个密封箱内装着部件和系统，法拉一眼就认出它们极其稀有，可能是原型级硬件；即使能在公开市场买到，价格也会高得惊人。</color>

<color=#BFBFBF>达吕斯又检查了一遍清单。</color>“两千万 C-币、一台突击机甲、带弹药储备的部落武器技术，还有先进设备。马库斯说这是对核威胁的补偿和道歉费。我想他确实是认真的。”

<color=#BFBFBF>杨用手抚过突击机甲的装甲板。</color>“这是我们应得的。我们阻止了灭绝武器，还在冰冻地狱般的星球上连续打了两场战斗。无论如何，这些东西也只能勉强弥补我们的损失。”

<color=#BFBFBF>明尼苏达部落运输船与<i>阿戈</i>号分离，开始执行离港程序。没有后续通讯，没有仪式，只有交付与离开。</color>

<color=#BFBFBF>达吕斯合上清单文件。</color>“好了，回去做普通的雇佣兵工作吧。只不过现在我们终于有钱把事情做得像样了。”

<color=#BFBFBF>几小时后，马库斯·哈默里克发来最后一条加密消息。没有文字，只有更新后的星图，标出了明尼苏达部落在边疆深处的真实聚居地。这是信任的表示，也可能是在警告我们永远不要去寻找他们。</color>

<color=#BFBFBF>其余奖励还放在货舱里。它们证明了<i>弗罗伊斯兰迪斯 VII</i>上的噩梦确实发生过，也确实已经结束。</color>
'@
    }
    if ($rel -like '*Weapon_Laser_Siege_Heavy.json' -and
        ($value.StartsWith('The "Titan') -or $value.StartsWith('The \"Titan'))) {
        return '“泰坦之矛”重型攻城激光炮由阿尔捷梅夫武器公司在高度机密的“泰坦计划”下研发，是专供超重型单位使用的攻城激光炮进化型。它专为定点射击设计，搭载机甲保持静止时能最大限度地维持能量相干性。在完全稳定的状态下，它能释放毁灭性光束，汽化铁钢并突破防御工事。巨大的功率需求、极高的热量和漫长的校准延迟，使它不适合较轻的平台。它虽然稀有，却能对战场产生巨大影响。飞行员报告称，开火时会出现传感器干扰和驾驶舱黑屏；阿尔捷梅夫武器公司尚未证实这些现象，但它们确实显示出这件武器的惊人强度。'
    }
    if ($rel -like '*event_co_BearingDownAddahBearing_Fallback.json') {
        if ($value.StartsWith("You're halfway through reviewing drop logistics")) {
            return @'
你正在数据板上查看空投后勤安排，达吕斯从你的舱室门口探出头来，神情介于若无其事和心虚之间。

“指挥官，”他开口，故意拖长语调，仿佛想把坏消息说得委婉些。“你还记得今天的日程吗？”

你抬头看向屏幕。“我应该记得吗？”

他拿着一份皱巴巴的行动日历走进房间。“怨恨试炼。贝林的。就是你答应要‘参加’的那场？”

你眨了眨眼，随后呻吟一声。“对，星蝰氏族的传统。我说过要作为他的见证人到场。”

“没错，”达吕斯点头说。“而且今天就开始。我想在你再次钻进引擎诊断，或者决定和餐厅咖啡机打一架之前提醒你。”

你叹了口气，起身抓起外套。“这是他应得的支持。我不会错过。”

“是吗？你差点就错过了，”达吕斯说，努力装出严肃的样子，却还是露出了笑容。“杨已经带了几名船员前往试炼场。听说贝林已经完全进入部落模式了——沉默、冷峻、让人害怕。应该会很精彩。”

你穿上外套，查看腕上计时器。“告诉菫保持一艘穿梭机待命。如果贝林赢下试炼，我们可能得比预计更早给他重新安排铺位。”

达吕斯用两根手指敬了个礼。“明白。还有，结束时别忘了戏剧性地鼓掌。部落战士喜欢这一套。”

你经过他身边时摇了摇头。“把我的座位留好就行。”

“观众席，还是指挥官席？”他在身后喊道。

你没有回答，因为你已经走出了舱门。
'@
        }
        if ($value.StartsWith('You stand on the paved surface')) {
            return @'
你站在试炼场铺砌的地面上，远处发电机的低鸣隐约穿过微风。铁灰色的天空映照着空气中的紧张气氛。贝林穿着战斗装甲从场地另一端走来，尽管装甲沾满尘土、历经磨损，部落徽记仍在闪耀。

“这是一段……旅程。”他望着前方说道，透过打开的面罩可以看见他的双眼，仿佛心神仍走在那条路上。“我与星蝰氏族共度的时光充满纪律、挑战——以及理解。”

你点头聆听，双臂交叉。“现在轮到你的怨恨试炼了，”你压低声音说。“洗清荣誉污点，赢得血名。”

贝林转向你。“是。我获得 Banacek 之名的资格，必须靠自己赢得，并由见证者确认和尊重。”

你向前迈步，脚下碎石发出声响。“那我会在场。”你语气坚定。“如果这是让你回到连队所必须付出的代价，我会亲眼见证。”

部落战士一贯冷漠的表情出现了细微裂缝，闪过一丝感激。“你的存在让我更强，指挥官。我战斗不只是为了自己，也是为了回到曾经离开的地方。”

你伸出手点了点头。“你一直是我们的一员，贝林。过去如此，现在也是。我毫不怀疑你会在试炼中证明这一点。”

他用传统机甲战士的方式紧紧握住你的前臂，坚定地说：“那就这么办。”

你转身发现达吕斯已经在附近来回踱步，手里拿着数据板，显然在努力装作若无其事。

“达吕斯。”你叫他。他立刻精神起来，仿佛你刚递给他一份标着“紧急”的打捞报告。

“来了！试炼后勤、运输、仪式出席——交给我。”他已经开始在数据板上敲击。“我会给我们安排前排观众席。”

“很好。”你转身对贝林说。“让我们确保这场试炼成为守望者议会永远不会忘记的事情。”

贝林深深点头，声音如钢铁般坚定。“他们会记住的，指挥官。无论输赢，他们都会<i>知道</i>我的名字。”

<color=#FF0000>战斗合约：贝林的位置已添加到指挥中心</color>
'@
        }
    }
    if ($rel -like '*event_co_BearingDownAddahBearing.json') {
        if ($value.StartsWith('The neon lights')) {
            return @'
偏远酒吧的霓虹灯映照着昏暗的环境。你坐在吧台边慢慢喝着酒，几名客人笼罩在一片异样的光芒中。达吕斯，你那忠诚却有些笨手笨脚的副官，正在酒吧另一头翻弄一叠情报报告，眉头因专注而紧皱。

你环顾房间，目光落在靠墙站立的人影上。他穿着一眼就能认出的机甲战士装备。是贝林。将近一年以前，他离开{COMPANY.CompanyName}，踏上了前往星蝰氏族的个人旅程；如今他像一名沉默的哨兵站在那里。

你点头示意贝林过来。他迈着老练战士自信的步伐穿过房间。走近后，你看到他脸上刻着疲惫，那是他离开期间经历试炼的证明。

“{COMMANDER.FirstName} {COMMANDER.LastName}指挥官。”他恭敬地点头问候，声音因多年的战斗而低沉沙哑。“很高兴再次见到你。”

“我也是，贝林。”你指了指身旁的座位。“没想到会在<i>{TGT_SYSTEM.Name}</i>看到你。”

贝林眼中闪过一丝决意。“我在星蝰氏族的任务即将完成，”他解释道。“但在重新加入连队之前，我必须在这里进行一场怨恨试炼。”

你惊讶地扬起眉毛。“怨恨试炼？在这里？”你环视这间破旧的酒吧，既觉得好笑又难以置信。“好吧，我想更奇怪的事情也不是没发生过。”

达吕斯没有察觉这场谈话的分量，紧紧抱着一叠报告走过来加入你们。

“指挥官，最新的情报报告在这里。”他得意地宣布，却被椅子绊了一下，差点把文件撒满地板。

你在心里叹了口气，和贝林交换了一个心照不宣的眼神，然后转向达吕斯挤出微笑。“谢谢你，达吕斯。不过这件事先放一放吧，我们还有更要紧的事情要处理。”
'@
        }
        if ($value.StartsWith('As Bearing tells you of his time away') -and $value -notmatch 'weight settles') {
            return @'
贝林向你讲述离开{COMPANY.CompanyName}后的经历，以及即将到来的怨恨试炼。你理解地点了点头。“我明白了。”你若有所思地说，手指轻敲杯沿。“如果这是你重新加入我们前必须完成的事，那我会去见证。”

贝林的表情因感激而明亮起来。“谢谢你，{COMMANDER.FirstName} {COMMANDER.LastName}指挥官。”他诚恳地说。“你的支持对我意义重大。”

你给了他一个令人安心的微笑。“当然，贝林。毕竟我仍然把你当作我们的一员，而且我完全相信你会成功。”

计划开始落实后，你转向达吕斯。“达吕斯，安排我们参加贝林的怨恨试炼。”你吩咐道。“越快出发越好。”

达吕斯点头，已经拿出数据板协调后勤。“交给我，指挥官。”他说完便匆匆离开去作准备。

你转回贝林，伸手表达同志般的情谊。“让我们确保这场试炼成为他们永远不会忘记的事情。”你坚定地说。

贝林用力握住你的手。“是，{COMMANDER.FirstName} {COMMANDER.LastName}。”他点头说。“我不会让你失望。”

<color=#FF0000>战斗合约：贝林的位置已添加到指挥中心</color>
'@
        }
        if ($value.StartsWith('As Bearing tells you of his time away') -and $value -match 'weight settles') {
            return @'
贝林向你讲述离开{COMPANY.CompanyName}后的经历，以及即将到来的怨恨试炼，一种沉重感在你胸中落下。“贝林，”你斟酌着措辞开口，“我很欣赏你对星蝰氏族的投入，也理解你为让自己变得更好而必须做的一切，但恐怕你离开后情况已经变了。”

贝林的神情发生变化。他直截了当地打断你，让你回想起他的脾气。“你不再需要我的服务，quineg？”他问道，声音里带着一丝怒意。

你深吸一口气，为接下来的艰难谈话做好准备。“你离开很久了，而{COMPANY.CompanyName}已经发生了巨大变化。”你遗憾地解释。“我不得不作出一些艰难决定，而且……恐怕这里已经没有你的位置了。”

贝林眯起眼睛，双拳紧握，却只是凝视着你，仿佛过了很久。“明白了，{COMMANDER.FirstName} {COMMANDER.LastName}。”

确认他不会突然发作后，你稍稍放松。“我也希望事情能有所不同。但形势逼得我不得不这么做，而且……”

贝林打断了你。他站起身，转身走出了酒吧。

达吕斯转向你。“指挥官，这不是一个容易作出的选择。”

你没有理会这句显而易见的话，目光锁定在缓缓合上的酒吧门上。思绪翻涌，你无法抑制地想：无论结果好坏，前路已经确定，只希望贝林能在未来的试炼中找到自己的道路。
'@
        }
    }
    if ($rel -like '*event_DeadMW_BaracasHacker_S.json' -and $value.StartsWith('You hand the datapad back to Yang')) {
        $cost = [regex]::Match($value, '¢([0-9,]+)').Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($cost)) { $cost = '1,900,000' }
        return @"
你把数据板递还给杨。“杨，谢谢你的辛苦。联系他们，让他们把这套<i>流浪熊战斗装甲</i>恢复正常运作。”

杨笑着接过数据板。“交给我，老板！”他前往机甲库时一路吹着口哨。

后来，你办公室的敲门声宣告杨回来了。“老板，工作完成了。现在任何有战斗装甲经验的人都能驾驶<i>巴拉卡斯</i>。”

你笑了笑。“这确实是个好消息。那么最后花了多少钱？”

杨低头看了看手里的数据板。“最终账单是 ¢$cost C-Bills。”

你皱了皱眉。“哎，至少还是比他们暗示的价格低。还有别的需要知道吗？”

杨点头。“有。解锁后的<i>巴拉卡斯</i>无法达到[[DEAD_MW,{DEAD_MW.Callsign}]]当初发挥出的同等性能。作战套件没能在解锁过程中幸存下来，所以它现在更像一套守护者 ECM。”
"@
    }
    if ($rel -like '*event_DeadMW_BaracasHacker_S.json' -and $value.StartsWith('You round the corner')) {
        $extra = if ($value -match 'refit it with gear') { '另外，由于这套装甲一直处于存放状态，作业完成后还需要整备并重新安装装备。' } else { '' }
        return @"
你在<i>阿戈</i>号的一条走廊转过拐角，与杨撞了个正着，文件和数据板散落一地。“抱歉，老板！我正要去找你。”

“没关系，杨。”你弯腰帮忙捡起掉落的物品。“什么事？”

杨把手里的数据板递给你。“老板，[[TGT_SYSTEM,{TGT_SYSTEM.Name}]]有人联系我们，回应我们关于解除[[DEAD_MW,{DEAD_MW.Callsign}]]那套<i>流浪熊战斗装甲</i>生物锁的询问。”

你接过数据板，浏览上面的信息。“所以他们要派技师来施展绝活，但没说要收多少钱？”

杨咳了一声，含糊地嘟囔着什么。“你刚才说什么？”你问。

杨清了清嗓子，重复道：“他们没有明确报价，但暗示解除生物锁要 ¢2,500,000。$extra”
"@
    }
    if ($rel -like '*event_co_RaysonAmbush*.json' -and
        ($value.StartsWith('You stare at the pirate on the viewscreen') -or $value.StartsWith('你盯着屏幕上的海盗'))) {
        return @'
你盯着屏幕上的海盗，他的面容明显被某种隐形滤镜遮蔽，然后回答道：“那么，我们怎么知道付钱之后你们就会放过我们？”

那个身影回应道：“好吧，坦白说，你们不知道。但你们还没有惹恼我，所以我愿意拿走报酬，让你们继续上路……继续这样下去，你们会看到我究竟能制造多大的混乱。”

就在这时，豹式从<i>阿戈</i>号侧面的对接环中脱离，向海盗舰船发射了一轮 LRM 弹幕。那些舰船躲开导弹，并向豹式和<i>阿戈</i>号还击。集中的激光炮火不断轰击船体，紧急系统随之启动，整艘<i>阿戈</i>号都在呻吟。双方的缠斗持续了一段时间，直到豹式一次极其精准的弹幕攻击重创一艘匪徒舰船。剩余舰船围绕受损同伴重新编队，随后脱离<i>阿戈</i>号远去。神秘身影发送了最后一条通讯：“看来你想试探我的决心，{COMMANDER.LastName}指挥官。记住我的话，我们<i>一定</i>会再次相遇。”

达吕斯喊道：“指挥官，<i>阿戈</i>号遭受了轻微损伤，舰上多处报告人员受伤，包括[[SCN_MW,{SCN_MW.Callsign}]]。{SCN_MW.Subj_C} {SCN_MW.Gender?已经|Default:已经}被送往医务室。”

随着海盗舰船消失在繁星点点的远方，你转向达吕斯：“他们是谁？他们到底是怎么知道我们的身份的？”

达吕斯从面板前抬起头，耸了耸肩：“我们的数据库里没有他们的记录。甚至他们的舰船上也没有任何标识或徽记。我能找到的关于这一地区匪徒活动的唯一记录，提到一名行踪神秘、名叫杰米·雷森（Jamie Rayson）的个人，以及他的搭档泡泡先生（Mr Bubbles），但那也不过只是传闻而已。”
'@
    }
    if ($rel -like '*pilot_Burtonias.json' -and $value.StartsWith('Occupying a rather odd place')) {
        return @'
在通常不信奉宗教的幽灵熊氏族中，伯特·奥尼亚斯，或者简称“伯特”，占据着相当奇特的位置。他在氏族内部拥有近乎崇拜的追随者，被许多人视为某种神祇。大家常称他为“圣伯特”，并在需要帮助或庇佑时向他祈求。由于这种崇拜不符合氏族传统，它并未被正式认定为宗教，但许多人敬重伯特的程度，几乎不亚于敬重尼古拉斯·凯伦斯基本人。圣伯特的崇拜如此强大，以至于它逐渐威胁到内圈更传统的宗教，尤其是那些同样带有邪教特征的信仰，并促使宗教领袖联合起来遏制其传播。

在神秘面纱背后，人们对伯特本人知之甚少。虽然普遍认为他出生于幽灵熊氏族真生战士的行列，但没有任何早年记录，氏族基因档案库也没有他的 DNA 样本。一些来源可疑的记录声称，他出生于狼氏族的育成群，后来在一次试炼后被并入幽灵熊氏族。不过要注意，伯特最狂热的信徒在别人质疑这些说法时可能会变得暴力。

无论他的出身是什么，有一点可以确定：伯顿尼亚斯在幽灵熊氏族中步步高升，最终成为萨汗。伯特与他的可汗“黑暗混沌”并肩作战，不懈扩张氏族领地，将这个原本中等规模的势力变成内圈真正的巨擘。

他如何获得“圣徒”称号，以及崇拜他的信仰如何形成，目前仍不得而知；看起来，伯特的崇拜仿佛凭空出现，并在出现时就已完整成形。

伯特拥有无数战场胜绩，是少有人能匹敌的可怕对手。他的军事才能还配合着氏族人少有的精明谈判手腕，常常无需派遣熊族战士上战场，就能以实力为后盾谈下新的领土。

伯特最后一次出现是在拉萨尔海格首都世界的阿斯加德战役中，当时他正在抵御云蛇氏族和所谓的“天穹幽灵”。虽然人们推测他已经战死，但从其机甲残骸中找到的记录显示，他在自己的机甲被摧毁前，曾击落多达三支云蛇氏族机甲星群。战后打捞队发现，伯特机甲的大部分区域都遭受灾难性损伤，驾驶舱却相对完整，只是里面空无一人。由于没有确凿证据证明这位萨汗已经死亡，他的神秘色彩反而更加浓厚；有人相信，距离他最后一次现身数十年后的今天，他仍然活着。

无论他是否还活着，幽灵熊氏族的许多人无疑仍会向圣伯特祈求熊之力量，以及伟大父亲的智慧，并让这份祈愿代代延续。
'@
    }
    if ($rel -like '*pilot_Grol.json' -and $value.StartsWith('David "Grol" Avellar')) {
        return @'
大卫·“格罗尔”·阿韦拉尔的母亲艾莉丝·阿韦拉尔被迫下台后，他成为外世界联盟第十三任总统。他既是出色的政治家，也是机甲战士，在外世界联盟动荡时期接任总统。他亲自参加过多场战役，抵抗新德尔斐协定和幽灵熊氏族的入侵。

幽灵熊入侵期间，阿韦拉尔身负致命重伤，依靠 ComStar 设计的实验性纳米机械治疗才活了下来。这次治疗让他严重毁容，直到接受雪鸦氏族提供的先进面部重建手术后，才恢复原貌。

多年的冲突给阿韦拉尔的心理带来了沉重负担。在接受雪鸦氏族心理战计划的思想灌输后，他逐渐形成不稳定的性格。他最终发动了一场夺取泰拉的灾难性远征，目标是狼氏族；这导致旧日盟友库里塔撕毁联盟并攻击阿韦拉尔的部队。随后阿韦拉尔把怒火转向旧日盟友，在库里塔控制的空间制造大片破坏，最终在距离龙蛇联合首都卢岑仅一跳之遥的地方被阻止。远征失败后，他消失了，雪鸦氏族接管了外世界联盟原有的领土。他最终的命运仍然未知。
'@
    }
    if ($rel -like '*pilot_Pagan.json' -and $value.StartsWith('Pagan Horde')) {
        return @'
帕甘·霍德是伯洛克氏族最受尊敬的可汗之一，也是所谓“杀人蜈蚣之道”的信奉者——至于那究竟是什么，没人说得清。在他统治的黄金时代，这位可汗大幅提升了这个原本弱小的氏族的力量与声望。

帕甘最终成为所有氏族的伊尔可汗，也是伯洛克氏族历史上仅有的两位做到这一点的可汗之一。入侵内圈的战斗模拟显示，伯洛克氏族能够建立一个横跨卡佩兰联邦、泰拉霸权和联邦太阳部分地区的庞大帝国。
'@
    }
    if ($rel -like '*pilot_SaphoTea.json' -and $value.StartsWith('While most well-known names')) {
        return @'
氏族社会中最广为人知的名字通常属于伟大战士，但也有少数人的名字能在群星之间闪耀，尽管他们并非战士。其中一个名字便是莱姆·林，石狮氏族的第一任伊尔奇。

莱姆以自由生身份出生于地狱马氏族，他的出身几乎注定了自己永远得不到成为伟大战士所需的训练和资源。虽然他足够优秀，能够作为坦克手加入氏族图曼，却注定无法与真生战士一同踏上征服内圈的道路。

幸运的是，这也让莱姆免于在劫掠战争后随地狱马氏族被逐出故乡。战马氏族遭到放逐后，莱姆成为氏族故乡残部的一员，并随之重组为新成立的石狮氏族。

许多人嘲笑这个新氏族是星蝰氏族的傀儡，但莱姆决心改变这种看法。氏族急需战士，他被征召进一线部队。凭借足以自保的实力和凝聚氏族的能力，他逐渐建立起名声；帮助真生战士面对失去旧氏族身份的痛苦后，甚至有几位真生战士开始仰望他。

3080 年 6 月，莱姆在一次试炼中偶然遇到即将成为郊狼氏族可汗的汉·希尔。那次试炼给希尔留下了深刻印象，也重新点燃了两个氏族之间的交流。那时莱姆还不知道，这次相遇会对他的未来产生多大影响。

随着两个氏族的沟通持续，莱姆越来越多地承担起与郊狼氏族联络的首席职责，并在这一职位上表现出色。两个氏族的关系改善后，石狮氏族的整体声望也随之提升。为了肯定莱姆的工作并进一步提高氏族地位，石狮氏族可汗决定恢复被遗忘已久的伊尔奇职位，并将其授予莱姆。

尽管真生战士中有些人提出异议，但大多数人都承认莱姆非常适合这个职位，而且正如人们所料，他把它做得极好。

在接下来的数年里，莱姆成功重塑了石狮氏族的形象，使氏族与凯伦斯基集群中的其他氏族关系密切，唯一的例外是血灵氏族。在莱姆的指导下，其他几个氏族也恢复了伊尔奇职位，他的名字逐渐为几乎所有氏族战士阶层所知。

莱姆·林去世时，人们普遍认为正是他让石狮氏族获得了氏族社会的认可。这不仅帮助可汗取得军事胜利，也扩大了氏族在凯伦斯基集群中的影响力。他无可匹敌的工作让最顽固的真生战士也看到了公关行动的价值，并为氏族间合作树立了新的标准。
'@
    }
    return $null
}

function Apply-JsonFile([IO.FileInfo]$file) {
    $rel = $file.FullName.Substring($mods.Length).TrimStart('\')
    $orig = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    $eventFields = 'Description|Details|Name|YangsThoughts|StockRole|levelName|decription|DisplayName|ErrorMessage|title|description|shortDescription|longDescription|FlashpointShortDescription|FlashpointLongDescription|words|Caption|label|Text|CULTURE_ZH_CN|UIName'
    $rx = [regex]('"(' + $eventFields + ')"\s*:\s*"((?:[^"\\]|\\.)*)"')
    $new = $rx.Replace($orig, {
        param($match)
        $field = $match.Groups[1].Value
        $value = Read-JsonString $match.Groups[2].Value
        if ($null -eq $value) { return $match.Value }
        if ($field -eq 'Name' -and
            $rel -notmatch '(?i)(?:^|[\\/])(?:event|forceevent|forcedevent)[^\\/]*\.json$') {
            return $match.Value
        }
        if ($field -eq 'Description' -and
            $rel -notmatch '(?i)^Flashpoints[\\/]FightingGhosts[\\/]mod\.json$') {
            return $match.Value
        }
        $zh = Translate-JsonDetails $rel ([string]$value)
        if ($null -eq $zh -or $zh -eq $value) { return $match.Value }
        $script:jsonReplaced++
        return ('"' + $field + '": ' + $ser.Serialize($zh))
    })
    if ($new -eq $orig) { return }
    try { [void]($ser.DeserializeObject($new)) } catch { throw "JSON 校验失败: $rel :: $($_.Exception.Message)" }
    Write-Backup $file.FullName $orig
    [IO.File]::WriteAllText($file.FullName, $new, $enc)
    $script:jsonChanged++
}

if (Test-Path $mods) {
    foreach ($file in Get-ChildItem -LiteralPath $mods -Recurse -File -Filter '*.json') {
        if ($file.FullName -like '*\.modtek\*' -or $file.FullName -match '[\\/]ModSaves[\\/]') { continue }
        Apply-JsonFile $file
    }
}

function Translate-CsvValue([string]$key, [string]$value) {
    if ($key.StartsWith('arelativenewcomertothesolarisscene')) {
        return $value.Replace('Quick Off The Line', '起步迅捷')
    }
    if ($key.StartsWith('themorningstarcitycommandvehicle')) {
        return $value.Replace('The Morningstar City Command Vehicle', '晨星城市指挥车').Replace('The Morningstar', '晨星')
    }
    if ($key.StartsWith('designedasthenextgenerationreplacementtotheageingignis')) {
        return $value.Replace('relegated to the pages of history', '被遗忘在历史长河中')
    }
    if ($key.StartsWith('ther10mechanizedinfantrycombatvehicle')) {
        return $value.Replace('R10 Mechanized Infantry Combat Vehicle (ICV)', 'R10 机械化步兵战车（ICV）')
    }
    if ($key.StartsWith('thescimitarmkiihovercombatvehicle')) {
        return $value.Replace('Scimitar Mk II Hover Combat Vehicle (HCV)', 'Scimitar Mk II 悬浮战斗载具（HCV）').Replace('venerable', '久负盛名的')
    }
    if ($key.StartsWith('amoderntakeonthevenerablesrm/lrmcarriers')) {
        return $value.Replace('JES II Strategic Missile Carrier', 'JES II 战略导弹载具').Replace('SRM/LRM Carrier', 'SRM/LRM 载具')
    }
    if ($key.StartsWith('introducedin3069andseeninlargenumbers')) {
        return $value.Replace('Oriente Model O Class', 'Oriente O 型')
    }
    if ($key.StartsWith('thewordofblakeintroducedanadvancedzhukov')) {
        return $value.Replace('venerable Demolisher', '久负盛名的 Demolisher')
    }
    if ($key.StartsWith('theswiftwindbuiltonindicass')) {
        return $value.Replace('Communications Equipment', '通信设备').Replace('Slippery Customer', '滑溜对手')
    }
    if ($key.StartsWith('name:goldthorpjerrisonmccalisteriiinewlinenewlinemechwarriormadlibbiography')) {
        return '<b>姓名：</b> Goldthorp Jerrison McCalister III\n\n机甲战士恶搞传记可以到这里。可持续的无麸质腌制 Four Loko。PBR 与讽刺让绿色果汁知识分子变得高档。你可能没听说过他们那套闪亮、谦虚、男人辫子、说真的、道德、云面包、奥斯汀直接贸易、苦味剂、奇亚籽法兰绒适应原和传家宝萨满；他们在喝醋和抽电子烟的本地食主义者之前就已经卖光了。'
    }
    if ($key.StartsWith('rasasameansbulletinarabic*theifritvtolstrikecraft')) {
        return 'Rasasa 在阿拉伯语中意为“子弹”。Ifrit VTOL 打击飞行器旨在拦截并延缓装甲推进；反应装甲、喷气助推器和 AMS 提高了它接近目标并部署挂架主要载荷的机会。Ifrit Rasasa 变体将基础型号的 SRM 换成高斯炮和中型激光。温压炸弹与 FASCAM 炸弹被替换为用于猎杀坦克的制导导弹。\n\n<b><color=#ffcc00>环境限制：该单位无法在月球环境部署。</color></b>\n<b><color=#ffcc00>移动：9/14 格 / 270/420 米。</color></b>\n<color=#ffcc00><b>装甲：</b>反应式装甲板\n<b>结构：</b>结构\n<b>数值      装甲      结构</b>\n<b>正面</b>      155          20\n<b>左侧</b>      115          20\n<b>右侧</b>      115          20\n<b>后方</b>       95          20\n\n<b>总计</b>      500         100</color>\n\n<color=#ff0000>特质：起步迅捷</color>\n#武器：\n  1x AMS MK2\n  1x 磁射炮\n  2x BrightBloom 中型增程激光\n  2x 箭 IV 导弹[翼挂]\n  2x AGM-10 导弹 x2[翼挂]\n  2x LAA 导弹[翼挂]'
    }
    if ($key.StartsWith('theasshurisaswifthovercraft')) {
        return 'Asshur 是一种快速的气垫船，设计用于迅速移动，以速度作为主要防御手段。一旦遭到攻击，只有三吨铁纤维装甲能够保护它。Asshur 的炮塔装有两门中型增程激光和一个锁定式 SRM-6 发射器。这些轻型武器威力强大，对其他车辆和轻型机甲构成可信威胁。然而，这种悬浮坦克最危险的能力是 TAG，它能引导友方箭 IV 发射器发射强大的寻的炮弹。\n\n<b><color=#ffcc00>环境限制：无。</color></b>\n<b><color=#ffcc00>移动：9/14 格 / 270/420 米。</color></b>\n<color=#ffcc00><b>装甲：</b>铁纤维（氏族）\n<b>结构：</b>结构\n<b>数值      装甲      结构</b>\n<b>正面</b>       65          10\n<b>左侧</b>       55          10\n<b>右侧</b>       55          10\n<b>后方</b>       45          10\n<b>炮塔</b>       60          10\n\n<b>总计</b>      280          50</color>\n\n<color=#ff0000>特质：灵活</color>\n#武器：\n  1x TAG\n  2x 中型增程激光（氏族）\n  1x 锁定式 SRM-6（氏族）'
    }
    if ($key.StartsWith('thepegasus(c)swapstheoriginalisweapons')) {
        $stats = if ($value -match 'front14520') { @('145','100','100','75','105','525') } else { @('140','100','100','65','110','515') }
        return "Pegasus（氏族）将原有的内圈武器替换为氏族科技替代品。它由回收残骸或作为战利品夺取的车辆建造，被分配给二线部队。\n\n<b><color=#ffcc00>环境限制：由于使用内燃机，该单位无法在月球或火星环境部署。</color></b>\n<b><color=#ffcc00>移动：8/12 格 / 240/360 米。</color></b>\n<color=#ffcc00><b>装甲：</b>装甲（氏族）\n<b>结构：</b>结构\n<b>数值      装甲      结构</b>\n<b>正面</b>       $($stats[0])          20\n<b>左侧</b>       $($stats[1])          20\n<b>右侧</b>       $($stats[2])          20\n<b>后方</b>       $($stats[3])          20\n<b>炮塔</b>      $($stats[4])          20\n\n<b>总计</b>      $($stats[5])         100</color>\n\n<color=#ff0000>特质：改良通信</color>\n#武器：\n  2x 小型增程激光（氏族）\n  2x 锁定式 SRM-6（氏族）"
    }
    if ($key.StartsWith('thisvariantofthethoris')) {
        return '这个 Thor 的变体试图将高速自行火炮转变为直接战斗单位。机械师用 AC/10、4 挺机枪和 2 个火箭发射器 20 替换了 Thumper 和中型激光。\n\n<b><color=#ffcc00>环境限制：无。</color></b>\n<b><color=#ffcc00>移动：4/6 格 / 120/180 米。</color></b>\n<color=#ffcc00><b>装甲：</b>装甲\n<b>结构：</b>结构\n<b>数值      装甲      结构</b>\n<b>正面</b>      135          30\n<b>左侧</b>      105          30\n<b>右侧</b>      105          30\n<b>后方</b>       90          30\n<b>炮塔</b>      105          30\n\n<b>总计</b>      540         150</color>\n\n<color=#ff0000>特质：精准武器 - 弹道</color>\n#武器：\n  1x AC/10\n  2x 双联机枪\n  2x 火箭 20'
    }
    if ($key.StartsWith('thisversionofthepadillaintroducedin3134')) {
        return '这个版本的 Padilla 于 3134 年推出，用与目标计算机相连的高斯步枪替换了标准 Padilla 的武器装备。不要与最初的 Padilla 混淆：Padilla 管式火炮坦克是球体共和国的一种载具，旨在履行类似任务。它最初由 Aldis Industries 应军事教长 Cameron St. Jamais 的要求设计和生产，是共和国武装部队使用的主要常规火炮支援平台。对于这种体型的载具来说，Padilla 防护良好；这很重要，因为它的最高速度较低，可能使它成为快速移动单位或空袭的容易目标。\n\n<b><color=#ffcc00>环境限制：无。</color></b>\n<b><color=#ffcc00>移动：3/5 格 / 90/150 米。</color></b>\n<color=#ffcc00><b>装甲：</b>载具隐身装甲\n<b>结构：</b>结构\n<b>数值      装甲      结构</b>\n<b>正面</b>      140          30\n<b>左侧</b>      125          30\n<b>右侧</b>      125          30\n<b>后方</b>       95          30\n<b>炮塔</b>      110          30\n\n<b>总计</b>      595         150</color>\n\n<color=#ff0000>特质：精准武器 - 弹道</color>\n#武器：\n  2x 高级 AMS\n  1x Blackwell 高斯步枪'
    }
    $eventTerms = Translate-EventTerms '' $value
    if ($null -ne $eventTerms) { return $eventTerms }
    return $null
}

if (Test-Path $csv) {
    $lines = [IO.File]::ReadAllLines($csv, [Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $comma = $lines[$i].IndexOf(',')
        if ($comma -lt 1) { continue }
        $key = $lines[$i].Substring(0, $comma)
        $oldValue = $lines[$i].Substring($comma + 1)
        $zh = Translate-CsvValue $key $oldValue
        if ($null -eq $zh -or $zh -eq $oldValue) { continue }
        if ($csvChanged -eq 0) { Write-Backup ([IO.Path]::GetFullPath($csv)) ([IO.File]::ReadAllText($csv, [Text.Encoding]::UTF8)) }
        $lines[$i] = $key + ',' + $zh
        $csvChanged++
    }
    if ($csvChanged -gt 0) { [IO.File]::WriteAllLines($csv, $lines, $enc) }
}

Write-Host ("残留候选修复: JSON files=" + $jsonChanged + " details=" + $jsonReplaced + " CSV rows=" + $csvChanged)
