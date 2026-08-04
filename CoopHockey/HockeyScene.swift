import SpriteKit

private struct Physics {
    static let puck:   UInt32 = 1 << 0
    static let mallet: UInt32 = 1 << 1
    static let wall:   UInt32 = 1 << 2
    static let goal:   UInt32 = 1 << 3
}

final class HockeyScene: SKScene, SKPhysicsContactDelegate {

    var onGoalScored: ((Int) -> Void)?
    /// Fires once per second of live NEMESIS play so the free trial only
    /// burns while the puck is actually moving.
    var onNemesisTrialTick: ((TimeInterval) -> Void)?
    private var nemesisTrialAccum: CGFloat = 0

    private var puckNode: SKShapeNode!
    private var mallet1: SKShapeNode!
    private var mallet2: SKShapeNode!

    private var goalWidth: CGFloat = 0
    private var puckRadius: CGFloat = 16
    private var malletRadius: CGFloat = 30

    var gameMode: GameMode = .twoPlayer

    // AI state — target is recomputed every frame; noise updates on a slow timer
    private var aiSmoothTarget: CGPoint = .zero
    private var aiNoiseX: CGFloat = 0
    private var aiNoiseTimer: CGFloat = 0

    // In-flight player shot, watched from strike until it crosses halfway so
    // PlayerModel can be told whether it was banked off a wall and how hard.
    private var shotInFlight = false
    private var shotBanked = false
    private var shotOriginX: CGFloat = 0
    private var shotSpeed: CGFloat = 0

    private var p1Touch: UITouch?
    private var p2Touch: UITouch?
    // Offset from finger to mallet center at the moment the mallet was grabbed,
    // so dragging keeps the same pickup-point on the mallet (no teleport snap).
    private var p1GrabOffset: CGPoint = .zero
    private var p2GrabOffset: CGPoint = .zero

    // Player can drag the puck briefly when it's stuck on their side (no AI to
    // rescue it, no auto-kick). Only active while puckTouch is held.
    private var puckTouch: UITouch?
    private var puckDragOffset: CGPoint = .zero
    private var puckDragVel: CGVector = .zero
    private var puckLastDragPos: CGPoint = .zero
    private var puckLastDragTime: TimeInterval = 0

    private var mallet1Target: CGPoint = .zero
    private var mallet2Target: CGPoint = .zero
    private var mallet1Vel: CGVector = .zero
    private var mallet2Vel: CGVector = .zero
    private var lastUpdateTime: TimeInterval = 0

    private(set) var isGameRunning = false
    private var pendingStart = false
    private var needsPuck = false
    private var puckTowardPlayer = 0
    private var goalCooldown = false
    private let maxPuckSpeed: CGFloat = 1100
    private var stuckTimer: CGFloat = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        // Transparent so SwiftUI scores rendered behind the SpriteView remain
        // visible — but get visually covered by any SKNode (puck/mallet) that
        // moves over them. The matching dark-green table color is supplied by
        // ContentView's outer Color view.
        backgroundColor = .clear
        view.allowsTransparency = true
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        view.isMultipleTouchEnabled = true
        // Setting size triggers didChangeSize, which calls buildTable() — don't call it here too
        size = view.bounds.size
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        removeAllChildren()
        buildTable()
        if pendingStart {
            pendingStart = false
            isGameRunning = true
            resetMalletPositions()
            needsPuck = true
            puckTowardPlayer = 0
        } else if isGameRunning {
            needsPuck = true
            puckTowardPlayer = 0
        }
    }

    // MARK: - Public API

    /// Reset the table for a new game but DON'T spawn the puck or start
    /// physics. Used so the coordinator can run a 3-2-1 countdown over an
    /// empty rink before releasing the puck.
    func prepareNewGame() {
        p1Touch = nil
        p2Touch = nil
        puckTouch = nil
        aiNoiseTimer = 0
        aiNoiseX = 0
        aiSmoothTarget = CGPoint(x: 0, y: size.height * 0.24)
        goalCooldown = false
        isGameRunning = false
        needsPuck = false
        puckTowardPlayer = 0
        lastUpdateTime = 0
        stuckTimer = 0
        pendingStart = false
        puckNode?.removeFromParent()
        puckNode = nil
        if mallet1 != nil {
            resetMalletPositions()
        }
        // Don't set pendingStart — launchGame() will arm needsPuck, and
        // update() correctly defers spawning until mallets exist.
    }

    /// Spawn the puck and start physics — called when the countdown finishes.
    func launchGame() {
        isGameRunning = true
        needsPuck = true
        puckTowardPlayer = 0
        lastUpdateTime = 0
        stuckTimer = 0
    }

    /// Convenience: prepare + immediately launch (no countdown). Kept for
    /// backwards compatibility, currently unused by the coordinator.
    func startGame() {
        prepareNewGame()
        launchGame()
    }

    func resumeAfterGoal(towardPlayer player: Int) {
        aiNoiseTimer = 0
        aiSmoothTarget = CGPoint(x: 0, y: size.height * 0.24)
        goalCooldown = false
        isGameRunning = true
        needsPuck = true
        puckTowardPlayer = player
        lastUpdateTime = 0
        stuckTimer = 0
    }

    func pauseGame()  { isPaused = true;  isGameRunning = false }
    func resumeGame() { p1Touch = nil; p2Touch = nil; isPaused = false; isGameRunning = true }

    private func resetMalletPositions() {
        let p1 = CGPoint(x: 0, y: -size.height * 0.22)
        let p2 = CGPoint(x: 0, y:  size.height * 0.22)
        mallet1?.position = p1
        mallet2?.position = p2
        mallet1Target = p1
        mallet2Target = p2
        mallet1Vel = .zero
        mallet2Vel = .zero
        mallet1?.physicsBody?.velocity = .zero
        mallet2?.physicsBody?.velocity = .zero
    }

    // MARK: - Table Construction

    private func buildTable() {
        let w = size.width, h = size.height
        goalWidth    = w * 0.42
        puckRadius   = min(w, h) * 0.044
        malletRadius = min(w, h) * 0.065

        drawVisuals()
        buildWalls()
        buildGoalSensors()
        buildMallets()
    }

    private func drawVisuals() {
        let w = size.width, h = size.height
        let bw: CGFloat = 3    // border inset
        let cr: CGFloat = 22   // corner radius
        let gw = goalWidth
        let goalDepth: CGFloat = 28

        let left = -w/2 + bw, right = w/2 - bw
        let top = h/2 - bw, bottom = -h/2 + bw
        let gpL = -gw/2, gpR = gw/2

        // Border as two subpaths — leaves goal-width gap at top and bottom
        let path = CGMutablePath()

        // Right half: gpR→top-right corner→right side→bottom-right corner→gpR (bottom)
        path.move(to: CGPoint(x: gpR, y: top))
        path.addLine(to: CGPoint(x: right - cr, y: top))
        path.addArc(center: CGPoint(x: right - cr, y: top  - cr), radius: cr, startAngle:  .pi/2, endAngle:  0,      clockwise: true)
        path.addLine(to: CGPoint(x: right, y: bottom + cr))
        path.addArc(center: CGPoint(x: right - cr, y: bottom + cr), radius: cr, startAngle:  0,     endAngle: -.pi/2, clockwise: true)
        path.addLine(to: CGPoint(x: gpR, y: bottom))

        // Left half: gpL (bottom)→bottom-left corner→left side→top-left corner→gpL (top)
        path.move(to: CGPoint(x: gpL, y: bottom))
        path.addLine(to: CGPoint(x: left + cr, y: bottom))
        path.addArc(center: CGPoint(x: left + cr, y: bottom + cr), radius: cr, startAngle: -.pi/2, endAngle: -.pi,   clockwise: true)
        path.addLine(to: CGPoint(x: left, y: top - cr))
        path.addArc(center: CGPoint(x: left + cr, y: top  - cr), radius: cr, startAngle:  .pi,    endAngle:  .pi/2, clockwise: true)
        path.addLine(to: CGPoint(x: gpL, y: top))

        let border = SKShapeNode(path: path)
        border.strokeColor = UIColor.white.withAlphaComponent(0.35)
        border.fillColor = .clear
        border.lineWidth = 3
        border.lineCap = .round
        border.lineJoin = .round
        border.zPosition = -9
        addChild(border)

        // Goal pockets — flush with border inner face, recessed into table
        let topPocketY = top    - goalDepth / 2
        let botPocketY = bottom + goalDepth / 2
        addGoalPocket(centerY: topPocketY, width: gw, depth: goalDepth,
                      color: UIColor(red: 0.12, green: 0.30, blue: 0.88, alpha: 0.55),
                      openFaceY: top)
        addGoalPocket(centerY: botPocketY, width: gw, depth: goalDepth,
                      color: UIColor(red: 0.88, green: 0.12, blue: 0.12, alpha: 0.55),
                      openFaceY: bottom)

        // Goal posts at inner corners of each opening
        for xOff in [gpL, gpR] {
            for yOff in [top, bottom] {
                let post = SKShapeNode(circleOfRadius: 6)
                post.position = CGPoint(x: xOff, y: yOff)
                post.fillColor = .white
                post.strokeColor = .clear
                post.zPosition = 1
                addChild(post)
            }
        }

        // Center line
        let solidLine = CGMutablePath()
        solidLine.move(to: CGPoint(x: left + cr/2, y: 0))
        solidLine.addLine(to: CGPoint(x: right - cr/2, y: 0))
        let dashedLine = solidLine.copy(dashingWithPhase: 0, lengths: [14, 9])
        let cl = SKShapeNode(path: dashedLine)
        cl.strokeColor = UIColor.white.withAlphaComponent(0.28)
        cl.lineWidth = 2
        cl.zPosition = -8
        addChild(cl)

        // Center circle
        let cc = SKShapeNode(circleOfRadius: malletRadius * 2.8)
        cc.fillColor = .clear
        cc.strokeColor = UIColor.white.withAlphaComponent(0.18)
        cc.lineWidth = 2
        cc.zPosition = -8
        addChild(cc)

        // Zone labels — inset past the goal pocket
        addZoneLabel(text: "P2", y: topPocketY - goalDepth/2 - 22,
                     color: UIColor(red: 0.15, green: 0.4, blue: 0.9, alpha: 0.22))
        addZoneLabel(text: "P1", y: botPocketY + goalDepth/2 + 22,
                     color: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.22))
    }

    // Three-sided goal pocket: open on the field-facing side (at openFaceY)
    private func addGoalPocket(centerY: CGFloat, width: CGFloat, depth: CGFloat,
                               color: UIColor, openFaceY: CGFloat) {
        let fill = SKShapeNode(rectOf: CGSize(width: width, height: depth))
        fill.position = CGPoint(x: 0, y: centerY)
        fill.fillColor = color
        fill.strokeColor = .clear
        fill.zPosition = -6
        addChild(fill)

        let hw = width / 2, hd = depth / 2
        let openY: CGFloat = openFaceY > centerY ? hd : -hd

        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: -hw, y:  openY))
        outline.addLine(to: CGPoint(x: -hw, y: -openY))
        outline.addLine(to: CGPoint(x:  hw, y: -openY))
        outline.addLine(to: CGPoint(x:  hw, y:  openY))

        let outlineNode = SKShapeNode(path: outline)
        outlineNode.strokeColor = UIColor.white.withAlphaComponent(0.38)
        outlineNode.lineWidth = 1.5
        outlineNode.zPosition = -5
        fill.addChild(outlineNode)
    }

    private func addZoneLabel(text: String, y: CGFloat, color: UIColor, rotate: Bool = false) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 30
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: y)
        label.zRotation = rotate ? .pi : 0
        label.zPosition = -7
        addChild(label)
    }

    // MARK: - Physics Bodies

    private func buildWalls() {
        let w = size.width, h = size.height
        let cr: CGFloat = 22   // matches visual border cornerRadius
        let i: CGFloat = 3     // inset to align with visual border stroke
        let gw = goalWidth

        let left = -w/2 + i, right = w/2 - i
        let top = h/2 - i, bottom = -h/2 + i
        let gpL = -gw/2, gpR = gw/2

        // Two edge-chain bodies that trace the EXACT same paths as the visible
        // border (see drawVisuals). Edge chains are infinitely thin so the
        // physics surface coincides with the visible wall — no hidden interior
        // disks at the corners (the old circular corner bumpers extended ~22pt
        // into the play area, causing puck to bounce off "ghost walls" near
        // the corners).

        // Right half: gpR(top) → top-right corner → right side → bottom-right → gpR(bottom)
        let pathR = CGMutablePath()
        pathR.move(to: CGPoint(x: gpR, y: top))
        pathR.addLine(to: CGPoint(x: right - cr, y: top))
        pathR.addArc(center: CGPoint(x: right - cr, y: top  - cr), radius: cr, startAngle:  .pi/2, endAngle:  0,      clockwise: true)
        pathR.addLine(to: CGPoint(x: right, y: bottom + cr))
        pathR.addArc(center: CGPoint(x: right - cr, y: bottom + cr), radius: cr, startAngle:  0,     endAngle: -.pi/2, clockwise: true)
        pathR.addLine(to: CGPoint(x: gpR, y: bottom))

        // Left half: gpL(bottom) → bottom-left corner → left side → top-left → gpL(top)
        let pathL = CGMutablePath()
        pathL.move(to: CGPoint(x: gpL, y: bottom))
        pathL.addLine(to: CGPoint(x: left + cr, y: bottom))
        pathL.addArc(center: CGPoint(x: left + cr, y: bottom + cr), radius: cr, startAngle: -.pi/2, endAngle: -.pi,   clockwise: true)
        pathL.addLine(to: CGPoint(x: left, y: top - cr))
        pathL.addArc(center: CGPoint(x: left + cr, y: top  - cr), radius: cr, startAngle:  .pi,    endAngle:  .pi/2, clockwise: true)
        pathL.addLine(to: CGPoint(x: gpL, y: top))

        addEdgeWall(path: pathR)
        addEdgeWall(path: pathL)
    }

    private func addEdgeWall(path: CGPath) {
        let node = SKNode()
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.restitution = 0.65
        body.friction = 0
        body.categoryBitMask    = Physics.wall
        body.collisionBitMask   = Physics.puck
        body.contactTestBitMask = Physics.puck
        node.physicsBody = body
        addChild(node)
    }

    private func buildGoalSensors() {
        let h = size.height
        // Deep sensor — catches the puck even if it tunnels several frames past
        // the table edge before the goal is registered.
        let depth: CGFloat = 400
        // Top sensor: P1 scores (puck entered P2's goal)
        addGoalSensor(CGRect(x: -goalWidth/2, y: h/2,     width: goalWidth, height: depth), name: "goal_p1")
        // Bottom sensor: P2 scores
        addGoalSensor(CGRect(x: -goalWidth/2, y: -h/2 - depth, width: goalWidth, height: depth), name: "goal_p2")
    }

    private func addGoalSensor(_ rect: CGRect, name: String) {
        let node = SKNode()
        node.name = name
        let body = SKPhysicsBody(rectangleOf: rect.size,
                                 center: CGPoint(x: rect.midX, y: rect.midY))
        body.isDynamic = false
        body.categoryBitMask    = Physics.goal
        body.collisionBitMask   = 0
        body.contactTestBitMask = Physics.puck
        node.physicsBody = body
        addChild(node)
    }

    private func buildMallets() {
        mallet1 = makeMallet(color: UIColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1))
        mallet1.position = CGPoint(x: 0, y: -size.height * 0.22)
        mallet1Target = mallet1.position
        addChild(mallet1)

        mallet2 = makeMallet(color: UIColor(red: 0.15, green: 0.35, blue: 0.92, alpha: 1))
        mallet2.position = CGPoint(x: 0, y:  size.height * 0.22)
        mallet2Target = mallet2.position
        addChild(mallet2)
    }

    private func makeMallet(color: UIColor) -> SKShapeNode {
        let outer = SKShapeNode(circleOfRadius: malletRadius)
        outer.fillColor = color
        outer.strokeColor = .white
        outer.lineWidth = 3
        outer.zPosition = 5

        let inner = SKShapeNode(circleOfRadius: malletRadius * 0.28)
        inner.fillColor = UIColor.white.withAlphaComponent(0.55)
        inner.strokeColor = .clear
        inner.zPosition = 6
        outer.addChild(inner)

        let body = SKPhysicsBody(circleOfRadius: malletRadius)
        body.isDynamic = false
        body.restitution = 0.85
        body.friction = 0
        body.categoryBitMask    = Physics.mallet
        body.collisionBitMask   = Physics.puck
        body.contactTestBitMask = Physics.puck
        outer.physicsBody = body
        return outer
    }

    // MARK: - Puck

    private func spawnPuck(toward player: Int) {
        puckNode?.removeFromParent()

        let puck = SKShapeNode(circleOfRadius: puckRadius)
        puck.fillColor = UIColor(white: 0.88, alpha: 1)
        puck.strokeColor = UIColor.white
        puck.lineWidth = 2.5
        puck.zPosition = 4
        puck.name = "puck"
        puck.position = .zero

        let body = SKPhysicsBody(circleOfRadius: puckRadius)
        body.isDynamic = true
        body.restitution = 0.82
        body.friction = 0.01
        body.linearDamping = 0.06
        body.allowsRotation = false
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask    = Physics.puck
        body.collisionBitMask   = Physics.wall | Physics.mallet
        body.contactTestBitMask = Physics.goal
        puck.physicsBody = body
        addChild(puck)
        puckNode = puck

        // Launch toward the player who didn't just score (or random on start)
        let dir: CGFloat = player == 2 ? -1 : 1
        let angle = CGFloat.random(in: -0.45...0.45)
        let speed: CGFloat = 210
        body.velocity = CGVector(dx: sin(angle) * speed, dy: dir * cos(angle) * speed)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let isVsComputer = gameMode != .twoPlayer
        // Comfortable grab area around the mallet — slightly larger than the
        // mallet itself so a thumb landing right next to it still picks it up,
        // but a tap far away won't teleport the mallet across the table.
        let grabRadius = malletRadius * 1.8
        let puckGrabRadius = puckRadius * 2.5

        for t in touches {
            let loc = t.location(in: self)
            var claimed = false

            // 1. Try to grab player 1's mallet (bottom half).
            if loc.y < 0, p1Touch == nil, mallet1 != nil {
                let d = hypot(loc.x - mallet1.position.x, loc.y - mallet1.position.y)
                if d <= grabRadius {
                    p1Touch = t
                    p1GrabOffset = CGPoint(x: mallet1.position.x - loc.x,
                                           y: mallet1.position.y - loc.y)
                    mallet1Target = mallet1.position
                    claimed = true
                }
            }

            // 2. Try to grab player 2's mallet (top half, 2-player only).
            if !claimed, loc.y >= 0, p2Touch == nil, !isVsComputer, mallet2 != nil {
                let d = hypot(loc.x - mallet2.position.x, loc.y - mallet2.position.y)
                if d <= grabRadius {
                    p2Touch = t
                    p2GrabOffset = CGPoint(x: mallet2.position.x - loc.x,
                                           y: mallet2.position.y - loc.y)
                    mallet2Target = mallet2.position
                    claimed = true
                }
            }

            // 3. If no mallet was grabbed and the puck is genuinely stuck on
            //    the player's side, allow the player to drag it free. Gating:
            //    must be in player half, puck must be near-stationary, and
            //    must have been stuck for at least a moment so accidental
            //    grabs during normal play don't trigger this.
            if !claimed, puckTouch == nil, let pn = puckNode, loc.y < 0 {
                let pSpd = hypot(pn.physicsBody?.velocity.dx ?? 0,
                                 pn.physicsBody?.velocity.dy ?? 0)
                if stuckTimer > 1.0 && pSpd < 60 {
                    let d = hypot(loc.x - pn.position.x, loc.y - pn.position.y)
                    if d <= puckGrabRadius {
                        puckTouch = t
                        puckDragOffset = CGPoint(x: pn.position.x - loc.x,
                                                 y: pn.position.y - loc.y)
                        puckLastDragPos = pn.position
                        puckLastDragTime = CACurrentMediaTime()
                        puckDragVel = .zero
                        pn.physicsBody?.velocity = .zero
                    }
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard mallet1 != nil, mallet2 != nil else { return }
        for t in touches {
            let loc = t.location(in: self)
            if t === p1Touch {
                let target = CGPoint(x: loc.x + p1GrabOffset.x,
                                     y: loc.y + p1GrabOffset.y)
                mallet1.position = clampMallet(target, half: .bottom)
            } else if t === p2Touch {
                let target = CGPoint(x: loc.x + p2GrabOffset.x,
                                     y: loc.y + p2GrabOffset.y)
                mallet2.position = clampMallet(target, half: .top)
            } else if t === puckTouch, let pn = puckNode {
                let target = CGPoint(x: loc.x + puckDragOffset.x,
                                     y: loc.y + puckDragOffset.y)
                // Clamp to play area. Cap Y at slightly below midline so the
                // player can't drag the puck across the center to cheat a
                // shot from the AI's half.
                let m = puckRadius + 4
                let hw = size.width / 2
                let hh = size.height / 2
                let clamped = CGPoint(
                    x: max(-hw + m, min(hw - m, target.x)),
                    y: max(-hh + m, min(-puckRadius * 1.5, target.y))
                )

                // Track recent motion for release-velocity calculation.
                let now = CACurrentMediaTime()
                let dt = max(0.001, now - puckLastDragTime)
                let vx = (clamped.x - puckLastDragPos.x) / CGFloat(dt)
                let vy = (clamped.y - puckLastDragPos.y) / CGFloat(dt)
                puckDragVel = CGVector(dx: puckDragVel.dx * 0.5 + vx * 0.5,
                                       dy: puckDragVel.dy * 0.5 + vy * 0.5)
                puckLastDragPos = clamped
                puckLastDragTime = now

                pn.physicsBody?.velocity = .zero
                pn.position = clamped
                stuckTimer = 0
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === p1Touch { p1Touch = nil }
            if t === p2Touch { p2Touch = nil }
            if t === puckTouch, let pn = puckNode {
                puckTouch = nil
                // Release with the puck's final flick velocity, capped so a
                // wild drag doesn't turn into a guaranteed goal.
                var v = puckDragVel
                let spd = hypot(v.dx, v.dy)
                let cap: CGFloat = 600
                if spd > cap {
                    let s = cap / spd
                    v = CGVector(dx: v.dx * s, dy: v.dy * s)
                }
                pn.physicsBody?.velocity = v
                puckDragVel = .zero
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private enum HalfCourt { case top, bottom }

    private func clampMallet(_ pos: CGPoint, half: HalfCourt) -> CGPoint {
        let m = malletRadius + 6
        let minX = -size.width / 2 + m
        let maxX =  size.width / 2 - m
        let minY: CGFloat
        let maxY: CGFloat
        switch half {
        case .bottom: minY = -size.height / 2 + m; maxY = -m
        case .top:    minY = m;                     maxY =  size.height / 2 - m
        }
        return CGPoint(x: max(minX, min(maxX, pos.x)),
                       y: max(minY, min(maxY, pos.y)))
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        guard isGameRunning, !goalCooldown, mallet1 != nil, mallet2 != nil else { return }

        if needsPuck {
            needsPuck = false
            spawnPuck(toward: puckTowardPlayer)
        }

        let dt = CGFloat(lastUpdateTime == 0 ? 0.016 : min(currentTime - lastUpdateTime, 0.05))
        lastUpdateTime = currentTime

        // This point is only reached while play is live (the guard above rules
        // out pauses, goal cooldowns and the pre-puck countdown), so it is the
        // right place to meter the trial.
        if gameMode == .vsComputer(.nemesis) {
            nemesisTrialAccum += dt
            if nemesisTrialAccum >= 1 {
                let whole = floor(nemesisTrialAccum)
                nemesisTrialAccum -= whole
                onNemesisTrialTick?(TimeInterval(whole))
            }
        }

        // Frame-rate-independent inertia decay (~0.4 s to stop)
        let decay = CGFloat(pow(0.88, Double(dt) * 60.0))

        if dt > 0 {
            if p1Touch != nil {
                mallet1Vel = CGVector(dx: (mallet1.position.x - mallet1Target.x) / dt,
                                     dy: (mallet1.position.y - mallet1Target.y) / dt)
            } else {
                mallet1Vel = CGVector(dx: mallet1Vel.dx * decay, dy: mallet1Vel.dy * decay)
                let drifted = CGPoint(x: mallet1.position.x + mallet1Vel.dx * dt,
                                     y: mallet1.position.y + mallet1Vel.dy * dt)
                mallet1.position = clampMallet(drifted, half: .bottom)
            }
            mallet1.physicsBody?.velocity = mallet1Vel

            if case .vsComputer(let diff) = gameMode {
                updateAI(dt: dt, difficulty: diff)
            } else {
                if p2Touch != nil {
                    mallet2Vel = CGVector(dx: (mallet2.position.x - mallet2Target.x) / dt,
                                         dy: (mallet2.position.y - mallet2Target.y) / dt)
                } else {
                    mallet2Vel = CGVector(dx: mallet2Vel.dx * decay, dy: mallet2Vel.dy * decay)
                    let drifted = CGPoint(x: mallet2.position.x + mallet2Vel.dx * dt,
                                         y: mallet2.position.y + mallet2Vel.dy * dt)
                    mallet2.position = clampMallet(drifted, half: .top)
                }
                mallet2.physicsBody?.velocity = mallet2Vel
            }
        }

        // Track last-frame position for per-frame velocity delta
        mallet1Target = mallet1.position
        mallet2Target = mallet2.position

        // Cap puck speed to prevent tunneling
        if let v = puckNode?.physicsBody?.velocity {
            let spd = hypot(v.dx, v.dy)
            if spd > maxPuckSpeed {
                let scale = maxPuckSpeed / spd
                puckNode.physicsBody?.velocity = CGVector(dx: v.dx * scale, dy: v.dy * scale)
            }
        }

        // Stuck-puck handling.
        // Player side: no auto-rescue. The human can drag the puck free with
        //   a touch when stuckTimer > 1.0 (see touchesBegan).
        // AI side: the AI mallet first tries to swing at the stuck puck via
        //   updateAI. If after ~2.5s it still hasn't connected (puck wedged
        //   in a corner geometry the AI can't reach cleanly), teleport the
        //   puck to a clean drop point — there's no human on that side to
        //   intervene, so a teleport is the only way to keep play moving.
        if let puck = puckNode, let body = puck.physicsBody {
            let spd = hypot(body.velocity.dx, body.velocity.dy)
            if spd < 55 { stuckTimer += dt } else { stuckTimer = 0 }

            let onAISide = puck.position.y > 0
            let aiHandlesIt = (gameMode != .twoPlayer) && onAISide
            if aiHandlesIt && stuckTimer > 2.5 {
                stuckTimer = 0
                let drop = aiSideDropPoint()
                puck.position = drop
                body.velocity = CGVector(dx: CGFloat.random(in: -80...80), dy: -260)
            }
        }

        // A watched shot completes once it reaches the AI half — that is the
        // point at which "did it bank on the way over" is settled.
        if shotInFlight, let puck = puckNode, puck.position.y > 0 {
            shotInFlight = false
            PlayerModel.shared.recordShot(
                originX: Double(shotOriginX / (size.width / 2)),
                speed: Double(shotSpeed),
                banked: shotBanked
            )
        }

        // Fallback positional goal detection (anti-tunnel safety net)
        if let puck = puckNode {
            let py = puck.position.y
            let px = puck.position.x
            if abs(px) < goalWidth / 2 {
                if py > size.height / 2 - puckRadius { triggerGoal(by: 1) }
                else if py < -size.height / 2 + puckRadius { triggerGoal(by: 2) }
            }
        }

        // Hard position clamp — final safety net so the puck can never escape
        // the visible play area through a corner seam. Only the goal column is
        // exempt (so legitimate scoring still works).
        if let puck = puckNode, !goalCooldown {
            let hw = size.width / 2
            let hh = size.height / 2
            let m = puckRadius + 4
            var p = puck.position
            let inGoalCol = abs(p.x) < goalWidth / 2 - puckRadius
            var clampedX = false, clampedY = false
            if p.x >  hw - m { p.x =  hw - m; clampedX = true }
            if p.x < -hw + m { p.x = -hw + m; clampedX = true }
            if !inGoalCol {
                if p.y >  hh - m { p.y =  hh - m; clampedY = true }
                if p.y < -hh + m { p.y = -hh + m; clampedY = true }
            }
            if clampedX || clampedY {
                puck.position = p
                // Reflect velocity off the clamped axis so it bounces naturally
                if let body = puck.physicsBody {
                    var v = body.velocity
                    if clampedX { v.dx = -v.dx * 0.6 }
                    if clampedY { v.dy = -v.dy * 0.6 }
                    body.velocity = v
                }
            }
        }
    }

    // MARK: - AI helpers

    /// A safe drop point in the AI's half (clear of the AI mallet) for the
    /// teleport rescue when the AI can't free a stuck puck on its own.
    private func aiSideDropPoint() -> CGPoint {
        let h = size.height
        let w = size.width
        let y: CGFloat = h * 0.18
        let candidates: [CGFloat] = [0, -w * 0.18, w * 0.18, -w * 0.30, w * 0.30]
        let minClear = (malletRadius + puckRadius) * 1.6
        for cx in candidates {
            let p = CGPoint(x: cx, y: y)
            let d2 = hypot(p.x - (mallet2?.position.x ?? 0),
                           p.y - (mallet2?.position.y ?? 0))
            if d2 > minClear { return p }
        }
        return CGPoint(x: 0, y: y)
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        guard isGameRunning, !goalCooldown else { return }
        let names = Set([contact.bodyA.node?.name, contact.bodyB.node?.name])
        if names.contains("goal_p1") { triggerGoal(by: 1) }
        else if names.contains("goal_p2") { triggerGoal(by: 2) }

        let aIsWall = contact.bodyA.categoryBitMask == Physics.wall
        let bIsWall = contact.bodyB.categoryBitMask == Physics.wall
        let aIsMallet = contact.bodyA.categoryBitMask == Physics.mallet
        let bIsMallet = contact.bodyB.categoryBitMask == Physics.mallet

        // Wall bounce sound + soft haptic
        if (aIsWall || bIsWall) {
            let puckBody = aIsWall ? contact.bodyB : contact.bodyA
            if puckBody.categoryBitMask == Physics.puck {
                let spd = hypot(puckBody.velocity.dx, puckBody.velocity.dy)
                if spd > 80 {
                    SFX.shared.playWall()
                    Haptics.shared.wallBounce(intensity: CGFloat(min(0.7, spd / 900)))
                }
                // A side wall (not an end wall) mid-shot means this was a bank.
                if shotInFlight, let pn = puckNode,
                   abs(pn.position.x) > size.width / 2 - puckRadius * 2.5 {
                    shotBanked = true
                }
            }
        }

        // Manual velocity transfer: SpriteKit treats isDynamic=false as a static wall,
        // ignoring its velocity for impulse calculations. We add the mallet-speed
        // component ourselves so a fast swipe actually launches the puck.
        guard aIsMallet || bIsMallet else { return }
        let aIsPuck = contact.bodyA.categoryBitMask == Physics.puck
        let bIsPuck = contact.bodyB.categoryBitMask == Physics.puck
        guard aIsPuck || bIsPuck else { return }
        guard let pn = puckNode else { return }

        let puckBody   = aIsPuck   ? contact.bodyA : contact.bodyB
        let malletNode = aIsMallet ? contact.bodyA.node : contact.bodyB.node

        let mv = (malletNode === mallet1) ? mallet1Vel : mallet2Vel

        // Collision normal: mallet center → puck center
        let dx = pn.position.x - (malletNode?.position.x ?? 0)
        let dy = pn.position.y - (malletNode?.position.y ?? 0)
        let dist = hypot(dx, dy)
        guard dist > 0 else { return }
        let nx = dx / dist, ny = dy / dist

        // Relative approach speed of mallet toward puck along normal
        let vRel = (mv.dx - puckBody.velocity.dx) * nx + (mv.dy - puckBody.velocity.dy) * ny
        guard vRel > 20 else { return }   // mallet meaningfully approaching

        // SpriteKit already applied: bounce off static wall  (-e · v_puck_normal)
        // We add:                    mallet speed component  ((1+e) · v_mallet_normal)
        // Combined = correct elastic result: (1+e)·v_mallet - e·v_puck  along normal
        let e: CGFloat = 0.80
        let j = (1 + e) * vRel * puckBody.mass
        puckBody.applyImpulse(CGVector(dx: nx * j, dy: ny * j))

        // Immediately cap post-impulse velocity so a single fast hit can't tunnel
        // through walls/sensors in one physics step (precise detection helps but
        // this guarantees the puck never starts a frame above maxPuckSpeed).
        let pv = puckBody.velocity
        let pvSpd = hypot(pv.dx, pv.dy)
        if pvSpd > maxPuckSpeed {
            let s = maxPuckSpeed / pvSpd
            puckBody.velocity = CGVector(dx: pv.dx * s, dy: pv.dy * s)
        }

        // Start watching a player shot that is heading for the AI half.
        if malletNode === mallet1, puckBody.velocity.dy > 60 {
            shotInFlight = true
            shotBanked   = false
            shotOriginX  = pn.position.x
            shotSpeed    = hypot(puckBody.velocity.dx, puckBody.velocity.dy)
        }

        // Hit sound — louder for faster strikes
        let malletSpeed = hypot(mv.dx, mv.dy)
        SFX.shared.playHit(speed: malletSpeed + CGFloat(vRel))

        // Haptic punch on the device that owns this mallet — scaled by impact
        // intensity so a soft tap is a soft tap and a swing is a thump.
        let totalSpeed = malletSpeed + CGFloat(vRel)
        Haptics.shared.puckHit(intensity: min(1.0, totalSpeed / 850))
    }

    // MARK: - AI

    private func updateAI(dt: CGFloat, difficulty: AIDifficulty) {
        guard let puck = puckNode, mallet2 != nil, dt > 0 else { return }

        let pv = puck.physicsBody?.velocity ?? .zero

        // Noise updates on a slow timer so aim wobbles gradually, not every frame
        aiNoiseTimer -= dt
        if aiNoiseTimer <= 0 {
            let jitter: CGFloat
            let interval: CGFloat
            switch difficulty {
            case .easy:    jitter = 55; interval = 0.35
            case .medium:  jitter = 14; interval = 0.18
            case .hard:    jitter =  3; interval = 0.08
            case .nemesis: jitter =  1; interval = 0.06
            }
            aiNoiseTimer = interval
            aiNoiseX = CGFloat.random(in: -jitter...jitter)
        }

        // Stuck-puck rescue (AI side): line up the mallet behind the puck and
        // swing through it toward the player's half — looks like a real strike,
        // not a teleport. Activates after the puck has been near-stationary on
        // the AI side for a moment.
        let puckSpd = hypot(pv.dx, pv.dy)
        let isStuckOnAISide = puck.position.y > 0 && puckSpd < 55 && stuckTimer > 0.35

        let rawTarget: CGPoint
        let responseTime: CGFloat
        let maxSpeed: CGFloat

        if isStuckOnAISide {
            // Approach from behind the puck (between puck and back wall) so the
            // contact normal pushes the puck toward center/player's half.
            let backOffset = malletRadius + puckRadius + 6
            let tx = puck.position.x          // line up directly behind
            let ty = puck.position.y + backOffset
            rawTarget = CGPoint(x: tx, y: ty)
            // Always swing aggressively regardless of difficulty so play resumes
            responseTime = 0.04
            maxSpeed = 720
            aiSmoothTarget = rawTarget        // skip smoothing — go now
        } else {
            // Normal play
            if difficulty == .nemesis {
                rawTarget = nemesisTarget(puck: puck, vel: pv)
                // Pressure earned from the player's record: a player who keeps
                // winning gets a quicker, faster opponent next time.
                let p = CGFloat(PlayerModel.shared.pressure)
                responseTime = 0.030 - 0.014 * p     // 0.030 → 0.016
                maxSpeed     = 660  + 230   * p      // 660   → 890
            } else {
                rawTarget = aiRawTarget(puck: puck, vel: pv)
                switch difficulty {
                case .easy:    responseTime = 0.30; maxSpeed = 195
                case .medium:  responseTime = 0.10; maxSpeed = 385
                case .hard:    responseTime = 0.03; maxSpeed = 650
                case .nemesis: responseTime = 0.03; maxSpeed = 650  // handled above
                }
            }
            let alpha = min(1, dt / responseTime)
            aiSmoothTarget.x += (rawTarget.x - aiSmoothTarget.x) * alpha
            aiSmoothTarget.y += (rawTarget.y - aiSmoothTarget.y) * alpha
        }

        // Move mallet toward smooth target at capped speed
        let dx = aiSmoothTarget.x - mallet2.position.x
        let dy = aiSmoothTarget.y - mallet2.position.y
        let dist = hypot(dx, dy)
        guard dist > 1 else {
            mallet2Vel = .zero
            mallet2.physicsBody?.velocity = .zero
            return
        }

        let step = min(dist, maxSpeed * dt)
        let newPos = CGPoint(x: mallet2.position.x + dx / dist * step,
                             y: mallet2.position.y + dy / dist * step)
        let clamped = clampMallet(newPos, half: .top)
        mallet2Vel = CGVector(dx: (clamped.x - mallet2.position.x) / dt,
                              dy: (clamped.y - mallet2.position.y) / dt)
        mallet2.position = clamped
        mallet2.physicsBody?.velocity = mallet2Vel
    }

    // Raw (ideal) target for the AI mallet, recomputed every frame.
    private func aiRawTarget(puck: SKShapeNode, vel: CGVector) -> CGPoint {
        let m  = malletRadius + 6
        let hw = size.width  / 2
        let hh = size.height / 2
        let clampX: (CGFloat) -> CGFloat = { max(-hw + m, min(hw - m, $0)) }
        let clampY: (CGFloat) -> CGFloat = { max(m,        min(hh - m, $0)) }

        if puck.position.y > 0 {
            // Puck in AI half — aim slightly behind it; use velocity to predict
            var tx: CGFloat
            if vel.dy > 40 {
                let t = max(0, min(0.4, (mallet2.position.y - puck.position.y) / vel.dy))
                tx = puck.position.x + vel.dx * t
            } else {
                tx = puck.position.x + vel.dx * 0.08
            }
            let ty = puck.position.y - malletRadius * 0.5
            return CGPoint(x: clampX(tx + aiNoiseX), y: clampY(ty))
        } else {
            // Puck in player half — sit at home, loosely shadow puck X
            return CGPoint(x: clampX(puck.position.x + aiNoiseX),
                           y: clampY(size.height * 0.24))
        }
    }

    // MARK: - NEMESIS

    /// Where the puck will cross `targetY`, following it through side-wall
    /// bounces instead of extrapolating in a straight line.
    ///
    /// This is what closes the bank-shot hole in the other difficulties:
    /// `aiRawTarget` projects the puck's current heading and so commits to a
    /// spot the puck never reaches once it has caromed off a wall. Each bounce
    /// keeps its full vertical speed but loses lateral speed to restitution
    /// (wall 0.65 x puck 0.82), so the reflection is modelled, not mirrored.
    private func predictCrossingX(pos: CGPoint, vel: CGVector,
                                  targetY: CGFloat, maxBounces: Int) -> CGFloat? {
        var p = pos
        var v = vel
        let limit = size.width / 2 - puckRadius
        let wallLoss: CGFloat = 0.53

        for _ in 0...maxBounces {
            guard abs(v.dy) > 1 else { return nil }
            let t = (targetY - p.y) / v.dy
            guard t > 0 else { return nil }

            let x = p.x + v.dx * t
            if abs(x) <= limit { return x }          // clean run to the line

            // A side wall comes first: advance to it, reflect, keep going.
            guard abs(v.dx) > 1 else { return max(-limit, min(limit, x)) }
            let wallX: CGFloat = x > 0 ? limit : -limit
            let tw = (wallX - p.x) / v.dx
            guard tw > 0, tw < t else { return max(-limit, min(limit, x)) }
            p = CGPoint(x: wallX, y: p.y + v.dy * tw)
            v = CGVector(dx: -v.dx * wallLoss, dy: v.dy)
        }
        return nil
    }

    /// NEMESIS's mallet target. Three behaviours, chosen by where the puck is:
    /// intercept an incoming puck at its true (post-bounce) crossing point,
    /// strike a reachable puck at the player's weak side, or hold a goalie
    /// line between the puck and its own net.
    private func nemesisTarget(puck: SKShapeNode, vel: CGVector) -> CGPoint {
        let model = PlayerModel.shared
        let m  = malletRadius + 6
        let hw = size.width  / 2
        let hh = size.height / 2
        let clampX: (CGFloat) -> CGFloat = { max(-hw + m, min(hw - m, $0)) }
        let clampY: (CGFloat) -> CGFloat = { max(m,        min(hh - m, $0)) }

        let interceptY = hh * 0.42
        let speed = hypot(vel.dx, vel.dy)

        // Incoming: meet it where it will actually arrive.
        if vel.dy > 40, puck.position.y < interceptY {
            // A player who banks a lot earns deeper lookahead.
            let bounces = model.bankRate > 0.4 ? 3 : 2
            if let x = predictCrossingX(pos: puck.position, vel: vel,
                                        targetY: interceptY, maxBounces: bounces) {
                return CGPoint(x: clampX(x + aiNoiseX), y: clampY(interceptY))
            }
        }

        // In its half and slow enough to be struck: aim the return away from
        // where this player likes to be, instead of just blocking it back.
        if puck.position.y > 0, speed < 620 {
            let aimX = clampX(CGFloat(-model.sideBias) * hw * 0.62)
            let aimY = -hh                       // toward the player's goal
            let dx = puck.position.x - aimX
            let dy = puck.position.y - aimY
            let len = max(1, hypot(dx, dy))
            let behind = malletRadius + puckRadius + 4
            return CGPoint(x: clampX(puck.position.x + dx / len * behind + aiNoiseX),
                           y: clampY(puck.position.y + dy / len * behind))
        }

        // Puck is with the player: hold the line between it and the net,
        // shaded toward the third this player scores through most. This is
        // deliberately not "shadow the puck's x" — that is what made the
        // other difficulties look like they were mirroring the player.
        let goal = CGPoint(x: CGFloat(model.weakSideBias) * goalWidth * 0.28, y: hh)
        let dx = goal.x - puck.position.x
        let dy = goal.y - puck.position.y
        let len = max(1, hypot(dx, dy))
        let guardDepth = hh * 0.30
        return CGPoint(x: clampX(goal.x - dx / len * guardDepth + aiNoiseX),
                       y: clampY(goal.y - dy / len * guardDepth))
    }

    private func triggerGoal(by scorer: Int) {
        guard !goalCooldown else { return }
        goalCooldown = true
        isGameRunning = false

        // Which part of its own mouth NEMESIS just got beaten through.
        if scorer == 1, gameMode == .vsComputer(.nemesis), let puck = puckNode {
            PlayerModel.shared.recordGoalConceded(
                x: Double(puck.position.x / max(1, goalWidth / 2))
            )
        }
        shotInFlight = false

        puckNode?.physicsBody?.velocity = .zero
        puckNode?.physicsBody?.isDynamic = false

        // Snap puck back into the visible play area so it doesn't appear to vanish
        // when it tunnels past the table edge into the goal sensor.
        if let puck = puckNode {
            let h = size.height
            let edge = puckRadius + 4
            if puck.position.y >  h/2 - edge { puck.position.y =  h/2 - edge }
            if puck.position.y < -h/2 + edge { puck.position.y = -h/2 + edge }
        }

        SFX.shared.playGoal()
        Haptics.shared.goal()

        let flash = SKShapeNode(rectOf: size)
        flash.fillColor = scorer == 1
            ? UIColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 0.28)
            : UIColor(red: 0.15, green: 0.35, blue: 0.92, alpha: 0.28)
        flash.strokeColor = .clear
        flash.zPosition = 20
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))

        onGoalScored?(scorer)
    }
}
