//
// Created by Bq Lin on 2021/8/31.
// Copyright © 2021 Bq. All rights reserved.
//

import GLKit.GLKTextureLoader

class GLRenderer: NSObject {
    static let interopTextureSize = CGSize(width: 1024, height: 1024)
    let defaultFOBName: GLuint
    var viewSize: CGSize!
    var programName: GLuint!
    var vaoName: GLuint!

    typealias TexInfo = (target: GLenum, name: GLuint)
    var baseMapTex: TexInfo!
    var labelMapTex: TexInfo!

    var textureDimensionIndex: GLint!
    var mvpUniformIndex: GLint!

    var projectionMatrix: matrix_float4x4!
    var scaleMatrix: matrix_float4x4 = matrix_identity_float4x4

    var rotation: Float = 0
    var rotationIncrement: Float = 0

    init(FBOName: GLuint) {
        print("\(String(cString: glGetString(GLenum(GL_RENDERER)))) \(String(cString: glGetString(GLenum(GL_VERSION))))")
        defaultFOBName = FBOName

        super.init()
        vaoName = makeVAO()
    }

    let quadVertices: [AAPLVertex] = [
        .init(position: [-0.75, -0.75, 0, 1], texCoord: [0, 0]),
        .init(position: [+0.75, -0.75, 0, 1], texCoord: [1, 0]),
        .init(position: [-0.75, +0.75, 0, 1], texCoord: [0, 1]),

        .init(position: [+0.75, -0.75, 0, 1], texCoord: [1, 0]),
        .init(position: [-0.75, +0.75, 0, 1], texCoord: [0, 1]),
        .init(position: [+0.75, +0.75, 0, 1], texCoord: [1, 1]),
    ]
    func makeVAO() -> GLuint {
        var vaoName: GLuint = 0
        #if os(macOS)
            glGenVertexArraysAPPLE(1, &vaoName)
            GetGLError()
            glBindVertexArrayAPPLE(vaoName)
        #else
            glGenVertexArrays(1, &vaoName)
            glBindVertexArray(vaoName)
        #endif

        var bufferName: GLuint = 0
        glGenBuffers(1, &bufferName)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), bufferName)
        GetGLError()

        glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<AAPLVertex>.size * quadVertices.count, quadVertices, GLenum(GL_STATIC_DRAW))
        GetGLError()

        glEnableVertexAttribArray(0)
        let stride = MemoryLayout<AAPLVertex>.size
        var offset = MemoryLayout<AAPLVertex>.offset(of: \AAPLVertex.position)!
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(stride), UnsafeRawPointer(bitPattern: offset))
        GetGLError()

        glEnableVertexAttribArray(1)
        offset = MemoryLayout<AAPLVertex>.offset(of: \AAPLVertex.texCoord)!
        glVertexAttribPointer(1, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(stride), UnsafeRawPointer(bitPattern: offset))
        GetGLError()

        return vaoName
    }

    func destroyVAO(_ vaoName: GLuint) {
        var bufName: GLint = 0
        #if os(macOS)
            glBindVertexArrayAPPLE(vaoName)
        #else
            glBindVertexArray(vaoName)
        #endif

        for i: GLuint in 0 ..< 16 {
            glGetVertexAttribiv(i, GLenum(GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING), &bufName)
            if bufName != 0 {
                var name = GLuint(bufName)
                glDeleteBuffers(1, &name)
            }
        }
        var name = vaoName
        glDeleteVertexArrays(1, &name)
        GetGLError()
    }

    func buildProgram(vertexShaderURL: URL, fragmentShaderURL: URL) -> GLuint {
        var vsh, fsh: String
        do {
            vsh = try String(contentsOf: vertexShaderURL)
            fsh = try String(contentsOf: fragmentShaderURL)
        } catch {
            fatalError("无法读取着色器")
        }

        let programName = glCreateProgram()
        glBindAttribLocation(programName, 0, "inPosition")
        glBindAttribLocation(programName, 1, "inTexcoord")

        var versionString = String(cString: glGetString(GLenum(GL_SHADING_LANGUAGE_VERSION)))
        if let range = versionString.range(of: "OpenGL ES GLSL ES ") {
            versionString.removeSubrange(range)
        }
        let version = Int(Float(versionString)! * 100)
        vsh = "#version \(version)\n\(vsh)"
        var cStringSource = (vsh as NSString).utf8String

        let vShader = glCreateShader(GLenum(GL_VERTEX_SHADER))
        glShaderSource(vShader, 1, &cStringSource, nil)
        glCompileShader(vShader)
        log(shader: vShader)

        glAttachShader(programName, vShader)
        glDeleteShader(vShader)

        fsh = "#version \(version)\n\(fsh)"
        cStringSource = (fsh as NSString).utf8String

        let fShader = glCreateShader(GLenum(GL_FRAGMENT_SHADER))
        glShaderSource(fShader, 1, &cStringSource, nil)
        glCompileShader(fShader)
        log(shader: fShader)

        glAttachShader(programName, fShader)
        glDeleteShader(fShader)

        glLinkProgram(programName)
        log(program: programName)

        glUseProgram(programName)
        mvpUniformIndex = glGetUniformLocation(programName, "modelViewProjectionMatrix")
        assert(mvpUniformIndex >= 0, "Could not get MVP Uniform Index")

        var l = glGetUniformLocation(programName, "baseMap")
        assert(l >= 0, "Could not get sampler Uniform Index")
        glUniform1i(l, 0)

        l = glGetUniformLocation(programName, "labelMap")
        assert(l >= 0, "Could not get sampler Uniform Index")
        glUniform1i(l, 1)

        GetGLError()

        return programName
    }

    func updateState() {
        if rotation > 30 * .pi / 180 {
            rotationIncrement = -0.01
        } else if rotation < -30 * .pi / 180 {
            rotationIncrement = 0.01
        }
        rotation += rotationIncrement

        let t = matrix4x4_translation(0, 0, -2)
        let r = matrix4x4_rotation(rotation, 0, 1, 0)
        let modelView = matrix_multiply(t, r)
        var mvp = matrix_multiply(projectionMatrix, modelView)
        mvp = matrix_multiply(scaleMatrix, mvp)

        let components = MemoryLayout.size(ofValue: mvp) / MemoryLayout<Float>.size
        let value = withUnsafePointer(to: &mvp) {
            $0.withMemoryRebound(to: Float.self, capacity: components) { $0 }
        }
        glUniformMatrix4fv(mvpUniformIndex, 1, GLboolean(GL_FALSE), value)
    }

    func useInteropTextureAsBaseMap(_ name: GLuint) {
        let vurl = Bundle.main.url(forResource: "shader", withExtension: "vsh")!
        #if os(macOS)
            baseMapTex = (target: GLenum(GL_TEXTURE_RECTANGLE), name: name)
            let furl = Bundle.main.url(forResource: "shaderTexRect", withExtension: "fsh")!
        #else
            baseMapTex = (target: GLenum(GL_TEXTURE_2D), name: name)
            let furl = Bundle.main.url(forResource: "shaderTex2D", withExtension: "fsh")!
        #endif
        programName = buildProgram(vertexShaderURL: vurl, fragmentShaderURL: furl)

        #if os(macOS)
            textureDimensionIndex = glGetUniformLocation(programName, "textureDimensions")
            assert(textureDimensionIndex > 0, "No textureDimensions uniform in rectangle texture fragment shader")
            glUniform2f(textureDimensionIndex, GLfloat(GLRenderer.interopTextureSize.width), GLfloat(GLRenderer.interopTextureSize.height))
        #endif

        let labelMapUrl = Bundle.main.url(forResource: "Assets/QuadWithGLtoView", withExtension: "png")!
        do {
            let texInfo = try GLKTextureLoader.texture(withContentsOf: labelMapUrl, options: nil)
            labelMapTex = (texInfo.target, texInfo.name)
        } catch {
            fatalError("加载纹理错误，\(error)")
        }

        #if os(macOS)
        #else
            scaleMatrix = matrix4x4_scale(1, -1, 1)
        #endif
        rotationIncrement = 0.01
    }

    func useTextureFromFileAsBaseMap() {
        let baseMapUrl = Bundle.main.url(forResource: "Assets/Colors", withExtension: "png")!
        let labelMapUrl = Bundle.main.url(forResource: "Assets/QuadWithGLtoPixelBuffer", withExtension: "png")!

        do {
            var texInfo: GLKTextureInfo
            texInfo = try GLKTextureLoader.texture(withContentsOf: baseMapUrl, options: nil)
            baseMapTex = (texInfo.target, texInfo.name)

            texInfo = try GLKTextureLoader.texture(withContentsOf: labelMapUrl, options: nil)
            labelMapTex = (texInfo.target, texInfo.name)

        } catch {
            fatalError("加载纹理错误，\(error)")
        }

        let vurl = Bundle.main.url(forResource: "shader", withExtension: "vsh")!
        let furl = Bundle.main.url(forResource: "shaderTex2D", withExtension: "fsh")!
        programName = buildProgram(vertexShaderURL: vurl, fragmentShaderURL: furl)
        rotationIncrement = -0.01
    }

    func draw() {
        updateState()

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), defaultFOBName)
        glClearColor(1, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        glUseProgram(programName)

        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(baseMapTex.target, baseMapTex.name)
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(labelMapTex.target, labelMapTex.name)

        #if os(macOS)
            glBindVertexArrayAPPLE(vaoName)
        #else
            glBindVertexArray(vaoName)
        #endif
        glDrawArrays(GLenum(GL_TRIANGLES), 0, GLsizei(quadVertices.count))
        GetGLError()
    }

    func resize(_ size: CGSize) {
        viewSize = size
        glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
        let aspect = Float(size.width / size.height)
        projectionMatrix = matrix_perspective_right_hand(1, aspect, 0.1, 5)
    }
}

func GetGLError() {
    let err = glGetError()
    guard err != GL_NO_ERROR else { return }
    fatalError("GLError \(String(cString: GetGLErrorString(err)))")
    // GetGLError()
}

func log(shader: GLuint) {
    var status: GLint = 0
    glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
    if status == 0 {
        print("着色器编译失败")
    }
    var logLength: GLint = 0
    glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLength)
    if logLength > 0 {
        let log = malloc(Int(logLength)).bindMemory(to: GLchar.self, capacity: 1)
        glGetShaderInfoLog(shader, logLength, &logLength, log)
        let logString = String(cString: log).trimmingCharacters(in: .newlines)
        fatalError("着色器编译log：\(logString)")
        // log.deallocate()
    }
}

func log(program: GLuint) {
    var status: GLint = 0
    glGetProgramiv(program, GLenum(GL_LINK_STATUS), &status)
    if status == 0 {
        print("程序链接失败")
    }

    var logLength: GLint = 0
    glGetProgramiv(program, GLenum(GL_INFO_LOG_LENGTH), &logLength)
    if logLength > 0 {
        let log = malloc(Int(logLength)).bindMemory(to: GLchar.self, capacity: 1)
        glGetProgramInfoLog(program, logLength, &logLength, log)
        let logString = String(cString: log).trimmingCharacters(in: .newlines)
        fatalError("程序链接log：\(logString)")
        // log.deallocate()
    }
}
