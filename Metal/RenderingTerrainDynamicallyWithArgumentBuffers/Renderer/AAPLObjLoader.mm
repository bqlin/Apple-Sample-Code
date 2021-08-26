/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the AAPLObjLoader.
 This class manaully transforms attributes needed for the sample, such as vertex texture coordinates into vertex color.
*/

#import "AAPLObjLoader.h"
#include <stdio.h>

@implementation AAPLObjMesh
-(NSUInteger) vertexCount { return _vertexBuffer.length / sizeof(AAPLObjVertex); }
-(NSUInteger) indexCount { return _indexBuffer.length / sizeof(uint16_t); }
@end

@implementation AAPLObjLoader
{
    // Indexed positions, normals, uvs from ObjFile; to be collated into ObjVertices during face read
    std::vector<simd::float3>                   _positions;
    std::vector<simd::float3>                   _normals;
    std::vector<simd::float3>                   _colors;
    float                                       _boundingSphereRadius;
    
    // Map that holds all generated vertices to de-duplicate
    std::unordered_map<AAPLObjVertex, uint32_t> _vertexMap;
    
    id<MTLDevice>                               _device;
    std::vector<AAPLObjVertex>                  _vertices;
    std::vector<uint16_t>                       _indices;
}

// Buffer size used to store file data internally during read operations
static constexpr uint kBufferSize = 2048;

-(instancetype)initWithDevice:(id<MTLDevice>) device
{
    self = [super init];
    _device = device;
    return self;
}

-(void) clear
{
    _boundingSphereRadius = 0.0f;
    _indices.clear();
    _vertices.clear();
    _vertexMap.clear();
    _normals.clear();
    _colors.clear();
    _positions.clear();
}

// Create or retrieve an exisiting vertex from our current vertex buffer; we keep a hash map for fast lookups
-(uint32_t) createOrFindVertex:(const AAPLObjVertex&) vertex
{
    // Find vertex is a hashmap
    std::unordered_map<AAPLObjVertex, uint32_t>::iterator i = _vertexMap.find(vertex);
    if (i == _vertexMap.end())
    {
        // If not present, add to map and vertex list
        _vertexMap.insert(std::pair<AAPLObjVertex,uint>(vertex, _vertices.size()));
        _vertices.push_back(vertex);
        
        _boundingSphereRadius = fmax(_boundingSphereRadius, simd::length(vertex.position));
        
        return (uint32_t) (_vertices.size()) - 1;
    }
    else
    {
        // Return the previously found vertex index from the list
        return i->second;
    }
    
}


-(void) readLine: (NSData*)inLine lineNumber:(uint) inNumber
{
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    uint iv[4];
    uint ivn[4];
    uint ivt[4];
    
    if      (sscanf(((char*)inLine.bytes), "v %f %f %f", &x, &y, &z) == 3)  _positions.push_back( (simd::float3) {x,y,z} );
    else if (sscanf(((char*)inLine.bytes), "vt %f %f %f", &x, &y, &z) == 3) _colors.push_back( (simd::float3) {x,y,z} );
    else if (sscanf(((char*)inLine.bytes), "vn %f %f %f", &x, &y, &z) == 3) _normals.push_back( (simd::float3) {x,y,z} );
    else if (sscanf(((char*)inLine.bytes), "f %d/%d/%d %d/%d/%d %d/%d/%d %d/%d/%d", &iv[0], &ivt[0], &ivn[0], &iv[1], &ivt[1], &ivn[1], &iv[2], &ivt[2], &ivn[2], &iv[3], &ivt[3], &ivn[3]) == 12) // quad
    {
        uint indices[4];
        for (uint v = 0; v < 4; v++)
        {
            AAPLObjVertex vtx;
            vtx.position      = _positions[iv[v]-1];
            vtx.normal        = _normals[ivn[v]-1];
            vtx.color         = _colors[ivt[v]-1];
            indices[v]        = [self createOrFindVertex:vtx];
        }
        _indices.push_back(indices[0]);
        _indices.push_back(indices[1]);
        _indices.push_back(indices[2]);
        _indices.push_back(indices[0]);
        _indices.push_back(indices[2]);
        _indices.push_back(indices[3]);
    }
    else if (sscanf(((char*)inLine.bytes), "f %d/%d/%d %d/%d/%d %d/%d/%d", &iv[0], &ivt[0], &ivn[0], &iv[1], &ivt[1], &ivn[1], &iv[2], &ivt[2], &ivn[2]) == 9) // triangle
    {
        uint indices[3];
        for (uint v = 0; v < 3; v++)
        {
            AAPLObjVertex vtx;
            vtx.position      = _positions[iv[v]-1];
            vtx.normal        = _normals[ivn[v]-1];
            vtx.color         = _colors[ivt[v]-1];
            indices[v]        = [self createOrFindVertex:vtx];
        }
        _indices.push_back(indices[0]);
        _indices.push_back(indices[1]);
        _indices.push_back(indices[2]);
    }
}


// File loading entrypoint that loads an URL and extracts lines from it for further processing
-(AAPLObjMesh*) loadFromUrl:(NSURL*) inUrl
{
    [self clear];
    
    NSInputStream* is = [NSInputStream inputStreamWithURL:inUrl];
    assert(is != nil);
    [is open];
    
    uint8_t read_buffer[kBufferSize];
    
    // Begin of current line(part) within buffer
    uint8_t* begin_line         = read_buffer;
    
    // End of current line(part) within buffer
    uint8_t* end_line           = read_buffer;
    
    // End of valid data in the buffer
    uint8_t* end_buffer         = read_buffer;
    NSMutableData* line         = [NSMutableData data];
    uint lineNumber             = 0;
    
    // Run until we run out of buffer and the input stream has no more data to retrieve
    while(begin_line != end_buffer || [is hasBytesAvailable])
    {
        // Scan to end of buffer/end of line
        for (end_line = begin_line; (end_line < end_buffer) && (*end_line != '\n'); end_line++) {}
        
        // Append part of c-style string to line buffer
        [line appendBytes: begin_line length:end_line-begin_line];
        
        if (end_line == end_buffer)
        {
            // In case of out-of-buffer, read new data, reset buffer
            end_buffer = read_buffer + [is read:&read_buffer[0] maxLength:kBufferSize-1];
            begin_line = read_buffer;
        }
        else
        {
            // In case of end-of-line, push new line, reset line buffer
            [line appendBytes:"" length:1];
            [self readLine: line lineNumber:++lineNumber];
            [line setLength:0];
            begin_line = end_line+1;
        }
    }
    [is close];
    
    AAPLObjMesh* new_mesh = [[AAPLObjMesh alloc] init];

#if TARGET_OS_IOS
    const MTLResourceOptions storageMode = MTLResourceStorageModeShared;
#else
    const MTLResourceOptions storageMode = MTLResourceStorageModeManaged;
#endif
    
    // Generate buffers
    new_mesh.vertexBuffer =     [_device newBufferWithLength:(sizeof(AAPLObjVertex)*_vertices.size())         options:storageMode];
    new_mesh.indexBuffer =      [_device newBufferWithLength:(sizeof(uint16_t)*_indices.size())               options:storageMode];
    new_mesh.boundingRadius = _boundingSphereRadius;
    
    // Copy vertices
    memcpy(new_mesh.vertexBuffer.contents, _vertices.data(), sizeof(AAPLObjVertex) * _vertices.size());
#if TARGET_OS_OSX
    [new_mesh.vertexBuffer didModifyRange:NSMakeRange(0, new_mesh.vertexBuffer.length)];
#endif
    
    // Copy indices
    memcpy(new_mesh.indexBuffer.contents, _indices.data(), sizeof(uint16_t) * _indices.size());
#if TARGET_OS_OSX
    [new_mesh.indexBuffer didModifyRange:NSMakeRange(0, new_mesh.indexBuffer.length)];
#endif

    [self clear];
    return new_mesh;
}

@end
