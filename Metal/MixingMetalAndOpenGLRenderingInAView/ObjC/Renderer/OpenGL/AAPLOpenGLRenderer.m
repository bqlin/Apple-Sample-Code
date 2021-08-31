/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs OpenGL state setup and per frame rendering
*/

#import "AAPLOpenGLRenderer.h"
#import "AAPLMathUtilities.h"

#import <simd/simd.h>

@implementation AAPLOpenGLRenderer
{
    GLuint _defaultFBOName;
    CGSize _viewSize;
    GLuint _programName;
    GLuint _vaoName;

    GLenum _baseMapTexTarget;
    GLuint _baseMapTexName;
    GLenum _labelMapTexTarget;
    GLuint _labelMapTexName;

    GLint _textureDimensionIndex;
    GLint _mvpUniformIndex;

    matrix_float4x4 _projectionMatrix;
    matrix_float4x4 _scaleMatrix;

    float _rotation;
    float _rotationIncrement;
}

// Indicies to which we will set vertex array attibutes
// See buildVAO and buildProgram
enum {
    POS_ATTRIB_IDX,
    TEXCOORD_ATTRIB_IDX
};

- (instancetype)initWithDefaultFBOName:(GLuint)defaultFBOName
{
    self = [super init];
    if(self)
    {
        NSLog(@"%s %s", glGetString(GL_RENDERER), glGetString(GL_VERSION));

        // Build all of our objects and setup initial state here

        _defaultFBOName = defaultFBOName;

       _vaoName = [self buildVAO];

        _scaleMatrix = matrix_identity_float4x4;

    }

    return self;
}

- (void)useInteropTextureAsBaseMap:(GLuint)name
{
    _baseMapTexName = name;

    NSURL *vertexSourceURL = [[NSBundle mainBundle] URLForResource:@"shader" withExtension:@"vsh"];

#if TARGET_MACOS
    _baseMapTexTarget = GL_TEXTURE_RECTANGLE;
    NSURL *fragmentSourceURL = [[NSBundle mainBundle] URLForResource:@"shaderTexRect" withExtension:@"fsh"];
#else
    _baseMapTexTarget = GL_TEXTURE_2D;
    NSURL *fragmentSourceURL = [[NSBundle mainBundle] URLForResource:@"shaderTex2D" withExtension:@"fsh"];
#endif

    _programName = [self buildProgramWithVertexSourceURL:vertexSourceURL
                                   withFragmentSourceURL:fragmentSourceURL];

#if TARGET_MACOS
    _textureDimensionIndex = glGetUniformLocation(_programName, "textureDimensions");

    NSAssert(_textureDimensionIndex >= 0,
             @"No textureDimensions uniform in rectangle texture fragment shader");

    glUniform2f(_textureDimensionIndex, AAPLInteropTextureSize.width, AAPLInteropTextureSize.height);
#endif

    {
        NSError *error;

        NSURL *labelMapURL = [[NSBundle mainBundle] URLForResource:@"Assets/QuadWithGLtoView" withExtension:@"png"];

        NSDictionary *option = nil;//@{ GLKTextureLoaderOriginBottomLeft : @YES};

        GLKTextureInfo *texInfo = [GLKTextureLoader textureWithContentsOfURL:labelMapURL
                                                                     options:option
                                                                       error:&error];

        NSAssert(texInfo, @"Failed to load texture at %@: %@",
                 labelMapURL.absoluteString, error);
        
        _labelMapTexName = texInfo.name;
        _labelMapTexTarget = texInfo.target;
    }

#if TARGET_IOS || TARGET_TVOS
    _scaleMatrix = matrix4x4_scale(1, -1, 1);
#endif

    _rotationIncrement = 0.01;
}

- (void)useTextureFromFileAsBaseMap
{
    NSError *error;

    {
        NSURL *baseTextureURL = [[NSBundle mainBundle] URLForResource:@"Assets/Colors" withExtension:@"png"];

        NSDictionary *option = nil;// @{ GLKTextureLoaderOriginBottomLeft : @YES};

        GLKTextureInfo *texInfo = [GLKTextureLoader textureWithContentsOfURL:baseTextureURL
                                                                     options:option
                                                                       error:&error];

        NSAssert(texInfo, @"Failed to load texture at %@: %@",
                 baseTextureURL.absoluteString, error);

        _baseMapTexName = texInfo.name;
        _baseMapTexTarget = texInfo.target;
    }

    {
        NSURL *labelMapURL = [[NSBundle mainBundle] URLForResource:@"Assets/QuadWithGLtoPixelBuffer" withExtension:@"png"];

        NSDictionary *option = nil;// @{ GLKTextureLoaderOriginBottomLeft : @YES};

        GLKTextureInfo *texInfo = [GLKTextureLoader textureWithContentsOfURL:labelMapURL
                                                                     options:option
                                                                       error:&error];

        NSAssert(texInfo, @"Failed to load texture at %@: %@",
                 labelMapURL.absoluteString, error);

        _labelMapTexName = texInfo.name;
        _labelMapTexTarget = texInfo.target;
    }

    NSURL *vertexSourceURL = [[NSBundle mainBundle] URLForResource:@"shader" withExtension:@"vsh"];
    NSURL *fragmentSourceURL = [[NSBundle mainBundle] URLForResource:@"shaderTex2D" withExtension:@"fsh"];

    _programName = [self buildProgramWithVertexSourceURL:vertexSourceURL
                                   withFragmentSourceURL:fragmentSourceURL];

    _rotationIncrement = -0.01;
}

- (GLuint)buildVAO
{
    typedef struct
    {
        vector_float4 position;
        packed_float2 texCoord;
    } AAPLVertex;

    static const AAPLVertex QuadVertices[] =
    {
        { { -0.75, -0.75, 0.0, 1.0}, {0.0, 0.0} },
        { {  0.75, -0.75, 0.0, 1.0}, {1.0, 0.0} },
        { { -0.75,  0.75, 0.0, 1.0}, {0.0, 1.0} },

        { {  0.75, -0.75, 0.0, 1.0}, {1.0, 0.0} },
        { { -0.75,  0.75, 0.0, 1.0}, {0.0, 1.0} },
        { {  0.75,  0.75, 0.0, 1.0}, {1.0, 1.0} }
    };

    GLuint vaoName;

    glGenVertexArrays(1, &vaoName);
    glBindVertexArray(vaoName);

    GLuint bufferName;

    glGenBuffers(1, &bufferName);
    glBindBuffer(GL_ARRAY_BUFFER, bufferName);

    glBufferData(GL_ARRAY_BUFFER,  sizeof(QuadVertices), QuadVertices, GL_STATIC_DRAW);

    glEnableVertexAttribArray(POS_ATTRIB_IDX);

    GLuint stride = sizeof(AAPLVertex);
    GLuint positionOffset = offsetof(AAPLVertex, position);

    glVertexAttribPointer(POS_ATTRIB_IDX,
                          2,
                          GL_FLOAT,
                          GL_FALSE,
                          stride,
                          BUFFER_OFFSET(positionOffset));

    // Enable the position attribute for this VAO
    glEnableVertexAttribArray(TEXCOORD_ATTRIB_IDX);

    GLuint texCoordOffset = offsetof(AAPLVertex, texCoord);

    glVertexAttribPointer(TEXCOORD_ATTRIB_IDX,
                          2,
                          GL_FLOAT,
                          GL_FALSE,
                          stride,
                          BUFFER_OFFSET(texCoordOffset));

    GetGLError();

    return vaoName;
}

- (void)destroyVAO:(GLuint)vaoName
{
    GLuint index;
    GLuint bufName;

    // Bind the VAO so we can get data from it
    glBindVertexArray(vaoName);

    // For every possible attribute set in the VAO, delete the attached buffer
    for(index = 0; index < 16; index++)
    {
        glGetVertexAttribiv(index , GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, (GLint*)&bufName);
        if(bufName)
        {
            glDeleteBuffers(1, &bufName);
        }
    }

    glDeleteVertexArrays(1, &vaoName);

    GetGLError();
}

- (GLuint)buildProgramWithVertexSourceURL:(NSURL*)vertexSourceURL
                    withFragmentSourceURL:(NSURL*)fragmentSourceURL
{
    NSError *error;

    NSString *vertSourceString = [[NSString alloc] initWithContentsOfURL:vertexSourceURL
                                                                encoding:NSUTF8StringEncoding
                                                                   error:&error];

    NSAssert(vertSourceString, @"Could not load vertex shader source: %@", error);

    NSString *fragSourceString = [[NSString alloc] initWithContentsOfURL:fragmentSourceURL
                                                                encoding:NSUTF8StringEncoding
                                                                   error:&error];

    NSAssert(fragSourceString, @"Could not load fragment shader source: %@", error);
    
    GLuint prgName;

    GLint logLength, status;

    // String to pass to glShaderSource
    GLchar* sourceString = NULL;

    // Determine if GLSL version 140 is supported by this context.
    //  We'll use this info to generate a GLSL shader source string
    //  with the proper version preprocessor string prepended
    float  glLanguageVersion;

#if TARGET_IOS
    sscanf((char *)glGetString(GL_SHADING_LANGUAGE_VERSION), "OpenGL ES GLSL ES %f", &glLanguageVersion);
#else
    sscanf((char *)glGetString(GL_SHADING_LANGUAGE_VERSION), "%f", &glLanguageVersion);
#endif

    // GL_SHADING_LANGUAGE_VERSION returns the version standard version form
    //  with decimals, but the GLSL version preprocessor directive simply
    //  uses integers (thus 1.10 should 110 and 1.40 should be 140, etc.)
    //  We multiply the floating point number by 100 to get a proper
    //  number for the GLSL preprocessor directive
    GLuint version = 100 * glLanguageVersion;

    // Get the size of the version preprocessor string info so we know
    //  how much memory to allocate for our sourceString
    const GLsizei versionStringSize = sizeof("#version 123\n");

    // Create a program object
    prgName = glCreateProgram();

    glBindAttribLocation(prgName, POS_ATTRIB_IDX, "inPosition");
    glBindAttribLocation(prgName, TEXCOORD_ATTRIB_IDX, "inTexcoord");

    //////////////////////////////////////
    // Specify and compile VertexShader //
    //////////////////////////////////////

    // Allocate memory for the source string including the version preprocessor information
    sourceString = malloc(vertSourceString.length + versionStringSize);

    // Prepend our vertex shader source string with the supported GLSL version so
    //  the shader will work on ES, Legacy, and OpenGL 3.2 Core Profile contexts
    sprintf(sourceString, "#version %d\n%s", version, vertSourceString.UTF8String);

    GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertexShader, 1, (const GLchar **)&(sourceString), NULL);
    glCompileShader(vertexShader);
    glGetShaderiv(vertexShader, GL_INFO_LOG_LENGTH, &logLength);

    if (logLength > 0)
    {
        GLchar *log = (GLchar*) malloc(logLength);
        glGetShaderInfoLog(vertexShader, logLength, &logLength, log);
        NSLog(@"Vtx Shader compile log:%s\n", log);
        free(log);
    }

    glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &status);
    
    if (status == 0)
    {
        NSLog(@"Failed to compile vtx shader:\n%s\n", sourceString);
        return 0;
    }

    free(sourceString);
    sourceString = NULL;

    // Attach the vertex shader to our program
    glAttachShader(prgName, vertexShader);

    // Delete the vertex shader since it is now attached
    // to the program, which will retain a reference to it
    glDeleteShader(vertexShader);

    /////////////////////////////////////////
    // Specify and compile Fragment Shader //
    /////////////////////////////////////////

    // Allocate memory for the source string including the version preprocessor     information
    sourceString = malloc(fragSourceString.length + versionStringSize);

    // Prepend our fragment shader source string with the supported GLSL version so
    //  the shader will work on ES, Legacy, and OpenGL 3.2 Core Profile contexts
    sprintf(sourceString, "#version %d\n%s", version, fragSourceString.UTF8String);

    GLuint fragShader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragShader, 1, (const GLchar **)&(sourceString), NULL);
    glCompileShader(fragShader);
    glGetShaderiv(fragShader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar*)malloc(logLength);
        glGetShaderInfoLog(fragShader, logLength, &logLength, log);
        NSLog(@"Frag Shader compile log:\n%s\n", log);
        free(log);
    }

    glGetShaderiv(fragShader, GL_COMPILE_STATUS, &status);
    if (status == 0)
    {
        NSLog(@"Failed to compile frag shader:\n%s\n", sourceString);
        return 0;
    }

    free(sourceString);
    sourceString = NULL;

    // Attach the fragment shader to our program
    glAttachShader(prgName, fragShader);

    // Delete the fragment shader since it is now attached
    // to the program, which will retain a reference to it
    glDeleteShader(fragShader);

    //////////////////////
    // Link the program //
    //////////////////////

    glLinkProgram(prgName);
    glGetProgramiv(prgName, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar*)malloc(logLength);
        glGetProgramInfoLog(prgName, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s\n", log);
        free(log);
    }

    glGetProgramiv(prgName, GL_LINK_STATUS, &status);
    if (status == 0)
    {
        NSLog(@"Failed to link program");
        return 0;
    }

    glGetProgramiv(prgName, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar*)malloc(logLength);
        glGetProgramInfoLog(prgName, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s\n", log);
        free(log);
    }

    glUseProgram(prgName);

    // Setup common program input points
    _mvpUniformIndex = glGetUniformLocation(prgName, "modelViewProjectionMatrix");
    
    NSAssert(_mvpUniformIndex >= 0, @"Could not get MVP Uniform Index");

    {
        GLint samplerLoc = glGetUniformLocation(prgName, "baseMap");
        
        NSAssert(samplerLoc >= 0, @"Could not get sampler Uniform Index");

        // Indicate that the diffuse texture will be bound to texture unit 0
        GLint unit = 0;
        glUniform1i(samplerLoc, unit);
    }

    {
        GLint samplerLoc = glGetUniformLocation(prgName, "labelMap");
        
        NSAssert(samplerLoc >= 0, @"Could not get sampler Uniform Index");
        
        // Indicate that the diffuse texture will be bound to texture unit 0
        GLint unit = 1;
        glUniform1i(samplerLoc, unit);
    }

    GetGLError();

    return prgName;

}

- (void)updateState
{
    if(_rotation > 30*(M_PI/180.0f))
    {
        _rotationIncrement = -0.01;
    }
    else if(_rotation < -30*(M_PI/180.0f))
    {
        _rotationIncrement = 0.01;
    }
    _rotation += _rotationIncrement;

    matrix_float4x4 rotation = matrix4x4_rotation(_rotation, 0.0, 1.0, 0.0);
    matrix_float4x4 translation = matrix4x4_translation(0.0, 0.0, -2.0);
    matrix_float4x4 modelView = matrix_multiply(translation, rotation);

    matrix_float4x4 mvp = matrix_multiply(_projectionMatrix, modelView);
    mvp = matrix_multiply(_scaleMatrix, mvp);

    glUniformMatrix4fv(_mvpUniformIndex, 1, GL_FALSE, (GLfloat*)(&mvp));
}

- (void)draw
{
    [self updateState];

    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFBOName);

    glClearColor(1, 0, 0, 1);

    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(_programName);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(_baseMapTexTarget, _baseMapTexName);

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(_labelMapTexTarget, _labelMapTexName);

    glBindVertexArray(_vaoName);

    glDrawArrays(GL_TRIANGLES, 0, 6);

    GetGLError();
}

matrix_float4x4 matrix_perspective_gl(float fovyRadians, float aspect, float near, float far)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = (far + near) / (near - far);
    float ws = (2.0 * far * near) / (near - far);
    return matrix_make_rows(xs,  0,  0,  0,
                             0, ys,  0,  0,
                             0,  0, zs, ws,
                             0,  0, -1,  0);
}

- (void)resize:(CGSize)size
{
    _viewSize = size;
    glViewport(0, 0, size.width, size.height);

    float aspect = (float)size.width / size.height;
    _projectionMatrix = matrix_perspective_right_hand(1, aspect, .1, 5.0);
}

@end
