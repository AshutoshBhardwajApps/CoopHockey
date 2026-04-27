import SpriteKit

private struct Physics {
    static let puck:   UInt32 = 1 << 0
    static let mallet: UInt32 = 1 << 1
    static let wall:   UInt32 = 1 << 2
    static let goal:   UInt32 = 1 << 3
}

final class HockeyScene: SKScene, SKPhysicsContactDelegate {

    var onGoalScored: ((Int) -> Void)?

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

    private var p1Touch: UITouch?
    private var p2Touch: UITouch?

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

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = UIColor(red: 0.04, green: 0.13, blue: 0.06, alpha: 1)
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

    func startGame() {
        p1Touch = nil
        p2Touch = nil
        aiNoiseTimer = 0
        aiNoiseX = 0
        aiSmoothTarget = CGPoint(x: 0, y: size.height * 0.24)
        goalCooldown = false
        isGameRunning = false
        needsPuck = false
        puckTowardPlayer = 0
        lastUpdateTime = 0
        if mallet1 != nil {
            isGameRunning = true
            resetMalletPositions()
        } else {
            pendingStart = true
        }
        needsPuck = true
    }

    func resumeAfterGoal(towardPlayer player: Int) {
        aiNoiseTimer = 0
        aiSmoothTarget = CGPoint(x: 0, y: size.height * 0.24)
        goalCooldown = false
        isGameRunning = true
        needsPuck = true
        puckTowardPlayer = player
        lastUpdateTime = 0
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
                     color: UIColor(red: 0.15, green: 0.4, blue: 0.9, alpha: 0.22), rotate: true)
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
        let t: CGFloat = 20    // wall thickness
        let cr: CGFloat = 22   // matches visual border cornerRadius
        let i: CGFloat = 3     // inset to align with visual border stroke

        // Straight section lengths
        let sideH   = h - 2*i - 2*cr          // left/right wall height (between corners)
        let straightW = w/2 - i - cr - goalWidth/2  // top/bottom wall segment width

        // Left wall (inner face at -w/2 + i)
        addWall(CGRect(x: -w/2 + i - t, y: -(h/2 - i - cr), width: t, height: sideH))
        // Right wall (inner face at w/2 - i)
        addWall(CGRect(x:  w/2 - i,     y: -(h/2 - i - cr), width: t, height: sideH))

        // Top wall – left and right of goal opening (bottom face at h/2 - i)
        addWall(CGRect(x: -w/2 + i + cr, y: h/2 - i, width: straightW, height: t))
        addWall(CGRect(x:  goalWidth/2,  y: h/2 - i, width: straightW, height: t))

        // Bottom wall (top face at -h/2 + i)
        addWall(CGRect(x: -w/2 + i + cr, y: -h/2 + i - t, width: straightW, height: t))
        addWall(CGRect(x:  goalWidth/2,  y: -h/2 + i - t, width: straightW, height: t))

        // Circular corner bumpers — fill the gap left by the rounded visual corners
        let cornerOffsets: [CGPoint] = [
            CGPoint(x: -w/2 + i + cr, y:  h/2 - i - cr),
            CGPoint(x:  w/2 - i - cr, y:  h/2 - i - cr),
            CGPoint(x: -w/2 + i + cr, y: -h/2 + i + cr),
            CGPoint(x:  w/2 - i - cr, y: -h/2 + i + cr),
        ]
        for pt in cornerOffsets { addCornerBumper(at: pt, radius: cr) }
    }

    private func addWall(_ rect: CGRect) {
        let node = SKNode()
        let body = SKPhysicsBody(rectangleOf: rect.size,
                                 center: CGPoint(x: rect.midX, y: rect.midY))
        body.isDynamic = false
        body.restitution = 0.65
        body.friction = 0
        body.categoryBitMask    = Physics.wall
        body.collisionBitMask   = Physics.puck
        body.contactTestBitMask = Physics.puck
        node.physicsBody = body
        addChild(node)
    }

    private func addCornerBumper(at center: CGPoint, radius: CGFloat) {
        let node = SKNode()
        let body = SKPhysicsBody(circleOfRadius: radius, center: center)
        body.isDynamic = false
        body.restitution = 0.55
        body.friction = 0
        body.categoryBitMask    = Physics.wall
        body.collisionBitMask   = Physics.puck
        body.contactTestBitMask = Physics.puck
        node.physicsBody = body
        addChild(node)
    }

    private func buildGoalSensors() {
        let h = size.height
        let depth: CGFloat = 44
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
        puck.fillColor = UIColor(white: 0.16, alpha: 1)
        puck.strokeColor = UIColor.white.withAlphaComponent(0.85)
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
        for t in touches {
            let loc = t.location(in: self)
            if loc.y < 0, p1Touch == nil {
                p1Touch = t
                mallet1Target = clampMallet(loc, half: .bottom)
                mallet1.position = mallet1Target
            } else if loc.y >= 0, p2Touch == nil, !isVsComputer {
                p2Touch = t
                mallet2Target = clampMallet(loc, half: .top)
                mallet2.position = mallet2Target
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard mallet1 != nil, mallet2 != nil else { return }
        for t in touches {
            let loc = t.location(in: self)
            if t === p1Touch {
                mallet1.position = clampMallet(loc, half: .bottom)
            } else if t === p2Touch {
                mallet2.position = clampMallet(loc, half: .top)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === p1Touch { p1Touch = nil }
            if t === p2Touch { p2Touch = nil }
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

        // Fallback positional goal detection (anti-tunnel safety net)
        if let puck = puckNode {
            let py = puck.position.y
            let px = puck.position.x
            if abs(px) < goalWidth / 2 {
                if py > size.height / 2 - puckRadius { triggerGoal(by: 1) }
                else if py < -size.height / 2 + puckRadius { triggerGoal(by: 2) }
            }
        }
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

        // Wall bounce sound
        if (aIsWall || bIsWall) {
            let puckBody = aIsWall ? contact.bodyB : contact.bodyA
            if puckBody.categoryBitMask == Physics.puck {
                let spd = hypot(puckBody.velocity.dx, puckBody.velocity.dy)
                if spd > 80 { SFX.shared.playWall() }
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

        // Hit sound — louder for faster strikes
        let malletSpeed = hypot(mv.dx, mv.dy)
        SFX.shared.playHit(speed: malletSpeed + CGFloat(vRel))
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
            case .easy:   jitter = 55; interval = 0.35
            case .medium: jitter = 14; interval = 0.18
            case .hard:   jitter =  3; interval = 0.08
            }
            aiNoiseTimer = interval
            aiNoiseX = CGFloat.random(in: -jitter...jitter)
        }

        // Raw target is recomputed every frame — no stale target lag
        let rawTarget = aiRawTarget(puck: puck, vel: pv)

        // Smooth the AI towards the raw target. Response time controls difficulty feel:
        // slow smooth = AI appears to react late (easy), fast smooth = snappy (hard).
        let responseTime: CGFloat
        let maxSpeed: CGFloat
        switch difficulty {
        case .easy:   responseTime = 0.30; maxSpeed = 195
        case .medium: responseTime = 0.10; maxSpeed = 385
        case .hard:   responseTime = 0.03; maxSpeed = 650
        }
        let alpha = min(1, dt / responseTime)
        aiSmoothTarget.x += (rawTarget.x - aiSmoothTarget.x) * alpha
        aiSmoothTarget.y += (rawTarget.y - aiSmoothTarget.y) * alpha

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

    private func triggerGoal(by scorer: Int) {
        guard !goalCooldown else { return }
        goalCooldown = true
        isGameRunning = false

        puckNode?.physicsBody?.velocity = .zero
        puckNode?.physicsBody?.isDynamic = false

        SFX.shared.playGoal()

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
