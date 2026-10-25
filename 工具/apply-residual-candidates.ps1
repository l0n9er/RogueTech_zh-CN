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
    $gameRoot = Split-Path $mods -Parent
    $rel = $path.Substring($gameRoot.Length).TrimStart('\')
    $bak = Join-Path $backupRoot $rel
    $parent = Split-Path $bak -Parent
    if (-not (Test-Path $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $old, $enc) }
}

function Translate-JsonDetails([string]$rel, [string]$value) {
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
    $rx = [regex]'"Details"\s*:\s*"((?:[^"\\]|\\.)*)"'
    $new = $rx.Replace($orig, {
        param($match)
        $value = Read-JsonString $match.Groups[1].Value
        if ($null -eq $value) { return $match.Value }
        $zh = Translate-JsonDetails $rel ([string]$value)
        if ($null -eq $zh -or $zh -eq $value) { return $match.Value }
        $script:jsonReplaced++
        return ('"Details": ' + $ser.Serialize($zh))
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
