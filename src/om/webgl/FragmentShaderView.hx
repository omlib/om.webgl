package om.webgl;

import js.Browser.console;
import js.Browser.document;
import js.Browser.window;
import js.html.CanvasElement;
import js.html.Float32Array;
import js.html.webgl.Framebuffer;
import js.html.webgl.Renderbuffer;
import js.html.webgl.Buffer;
import js.html.webgl.GL;
import js.html.webgl.Program;
import js.html.webgl.Shader;
import js.html.webgl.RenderingContext;
import js.html.webgl.Texture;
import js.html.webgl.UniformLocation;

typedef RenderTarget = {
    var framebuffer : Framebuffer;
    var renderbuffer : Renderbuffer;
    var texture : Texture;
}

typedef Surface = {
    var centerX : Int;
    var centerY : Int;
    var width : Float;
    var height : Float;
    var buffer : Buffer;
    var positionAttribute : Int;
};

typedef Parameters = {
    //var startTime : Float;
    var time : Float;
    var mouseX : Float;
    var mouseY : Float;
    var screenWidth : Int;
    var screenHeight : Int;
    //var lastX : Int;
    //var lastY : Int;
};

//@:build(om.webgl.macro.BuildFragmentShaderView.build())
//@:autoBuild(om.webgl.macro.BuildFragmentShaderView.autoBuild())
class FragmentShaderView {

    public static var SCREEN_VS_SOURCE = '
attribute vec3 position;
void main() {
    gl_Position = vec4( position, 1.0 );
}';

    public static var SCREEN_FS_SOURCE = '
precision mediump float;
uniform vec2 resolution;
uniform sampler2D texture;
void main() {
    vec2 uv = gl_FragCoord.xy / resolution.xy;
    gl_FragColor = texture2D( texture, uv );
}';

    public static var defaultSurfaceVertexShaderSource = '
attribute vec3 position;
attribute vec2 surfacePosAttrib;
varying vec2 surfacePosition;
void main() {
    surfacePosition = surfacePosAttrib;
    gl_Position = vec4( position, 1.0 );
}';

    public dynamic function onError( info : String ) {}

    public var canvas(default,null) : CanvasElement;
    public var gl(default,null)  : RenderingContext;
    public var quality(default,null) : Float;
    public var parameters(default,null) : Parameters;

    //public var numRings = 100;
    //public var speed = 10.0;

    var surface : Surface;
    var buffer : Buffer;
    var frontTarget : Dynamic;
    var backTarget : Dynamic;
    var currentProgram : Program;
    var screenProgram : Program;
    var screenVertexPosition : Int;
    var vertexPosition : Int;

    public function new( canvas : CanvasElement, quality = 1.0, preserveDrawingBuffer = true ) {

        this.canvas = canvas;
        this.quality = quality;

        parameters = {
            time: 0,
            mouseX: 0.5, mouseY: 0.5,
            screenWidth: canvas.width, screenHeight: canvas.height,
            //lastX: 0, lastY: 0
        }

        gl = canvas.getContextWebGL( { preserveDrawingBuffer: preserveDrawingBuffer } );
        gl.getExtension('OES_standard_derivatives');

        buffer = gl.createBuffer();
        gl.bindBuffer( GL.ARRAY_BUFFER, buffer );
        gl.bufferData( GL.ARRAY_BUFFER, new Float32Array( [-1.0,-1.0,1.0,-1.0,-1.0,1.0,1.0,-1.0,1.0,1.0,-1.0,1.0] ), GL.STATIC_DRAW );

        surface = {
            centerX: 0, centerY: 0,
            width: 1, height: 1,
            buffer: gl.createBuffer(),
            positionAttribute : null
            //isPanning: false, isZooming: false,
            //lastX: 0, lastY: 0
        };

        gl.viewport( 0, 0, canvas.width, canvas.height );
        createRenderTargets();

        compileScreenProgram();
    }

    public function resize( width : Int, height : Int, ?quality : Float ) {

        if( quality != null ) this.quality = quality;

        canvas.width = Std.int( width / this.quality );
		canvas.height = Std.int( height / this.quality );
        canvas.style.width = width + 'px';
		canvas.style.height = height + 'px';

        parameters.screenWidth = canvas.width;
		parameters.screenHeight = canvas.height;

        computeSurfaceCorners();

        if( gl != null ) {
			gl.viewport( 0, 0, canvas.width, canvas.height );
			createRenderTargets();
		}
    }

    public function compile( fragmentShaderSource : String, ?surfaceVertexShaderSource : String ) {

        if( surfaceVertexShaderSource == null )
            surfaceVertexShaderSource = defaultSurfaceVertexShaderSource;

        var program = gl.createProgram();
        var vs = createShader( surfaceVertexShaderSource, GL.VERTEX_SHADER );
		var fs = createShader( fragmentShaderSource, GL.FRAGMENT_SHADER );
        if( vs == null || fs == null )
            return null;
        gl.attachShader( program, vs );
    	gl.attachShader( program, fs );
    	gl.deleteShader( vs );
    	gl.deleteShader( fs );
    	gl.linkProgram( program );
        if( gl.getProgramParameter( program, GL.LINK_STATUS ) == null ) {
            var error = gl.getProgramInfoLog( program );
            onError( error );
            return;
        }

        if( currentProgram != null ) gl.deleteProgram( currentProgram );

        currentProgram = program;

        //TODO cacheUniformLocations();

        cacheUniformLocation( program, 'time' );
		cacheUniformLocation( program, 'mouse' );
		cacheUniformLocation( program, 'resolution' );
		cacheUniformLocation( program, 'backbuffer' );
		cacheUniformLocation( program, 'surfaceSize' );

        cacheUniformLocations( program );
		//cacheUniformLocation( program, 'numRings' );
		//cacheUniformLocation( program, 'speed' );
        //cacheUniformLocation( program, 'direction' );

        gl.useProgram( currentProgram );

        surface.positionAttribute = gl.getAttribLocation( currentProgram, "surfacePosAttrib" );
        //TODO
        trace(surface.positionAttribute);
        //gl.enableVertexAttribArray( surface.positionAttribute );

        vertexPosition = gl.getAttribLocation( currentProgram, "position" );
		gl.enableVertexAttribArray( vertexPosition );
    }

    public function render( time : Float ) {

        if( currentProgram == null )
            return;

        parameters.time = time;

        // Set uniforms
		gl.useProgram( currentProgram );

		gl.uniform1f( untyped currentProgram.uniformsCache.time, time / 1000 );
		gl.uniform2f( untyped currentProgram.uniformsCache.mouse, parameters.mouseX, parameters.mouseY );
		gl.uniform2f( untyped currentProgram.uniformsCache.resolution, parameters.screenWidth, parameters.screenHeight );
		gl.uniform1i( untyped currentProgram.uniformsCache.backbuffer, 0 );
		gl.uniform2f( untyped currentProgram.uniformsCache.surfaceSize, surface.width, surface.height );

        setUniformsValues();
		//gl.uniform1f( untyped currentProgram.uniformsCache.numRings, numRings );
		//gl.uniform1f( untyped currentProgram.uniformsCache.speed, speed );
		//gl.uniform1i( untyped currentProgram.uniformsCache.direction, direction ? 0 : 1 );

		gl.bindBuffer( GL.ARRAY_BUFFER, surface.buffer );
        //TODO
        //trace(surface.positionAttribute);
        //gl.vertexAttribPointer( surface.positionAttribute, 2, GL.FLOAT, false, 0, 0 );

		gl.bindBuffer( GL.ARRAY_BUFFER, buffer );
		gl.vertexAttribPointer( vertexPosition, 2, GL.FLOAT, false, 0, 0 );

		gl.activeTexture( GL.TEXTURE0 );
		gl.bindTexture( GL.TEXTURE_2D, backTarget.texture );

        // Render custom shader to front buffer
		gl.bindFramebuffer( GL.FRAMEBUFFER, frontTarget.framebuffer );
		gl.clear( GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT );
		gl.drawArrays( GL.TRIANGLES, 0, 6 );

        // Set uniforms for screen shader
		gl.useProgram( screenProgram );
		gl.uniform2f( untyped screenProgram.uniformsCache.resolution, parameters.screenWidth, parameters.screenHeight );
		gl.uniform1i( untyped screenProgram.uniformsCache.texture, 1 );
		gl.bindBuffer( GL.ARRAY_BUFFER, buffer );
		gl.vertexAttribPointer( screenVertexPosition, 2, GL.FLOAT, false, 0, 0 );
		gl.activeTexture( GL.TEXTURE1 );
		gl.bindTexture( GL.TEXTURE_2D, frontTarget.texture );

        // Render front buffer to screen
		gl.bindFramebuffer( GL.FRAMEBUFFER, null );
		gl.clear( GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT );
		gl.drawArrays( GL.TRIANGLES, 0, 6 );

        // Swap buffers
		var tmp = frontTarget;
		frontTarget = backTarget;
		backTarget = tmp;
    }

    function cacheUniformLocations( program : Program ) {
        // override me
    }

    function setUniformsValues() {
        // override me
    }

    function cacheUniformLocation( program : Program, label : String ) {
        if( untyped program.uniformsCache == null )
            untyped program.uniformsCache = {};
		untyped program.uniformsCache[label] = gl.getUniformLocation( program, label );
    }

    function compileScreenProgram() {

        var program = gl.createProgram();
        var vs = createShader( SCREEN_VS_SOURCE, GL.VERTEX_SHADER );
		var fs = createShader( SCREEN_FS_SOURCE, GL.FRAGMENT_SHADER );
		gl.attachShader( program, vs );
	    gl.attachShader( program, fs );
		gl.deleteShader( vs );
		gl.deleteShader( fs );
		gl.linkProgram( program );
		if( !gl.getProgramParameter( program, GL.LINK_STATUS ) ) {
			onError( 'VALIDATE_STATUS: ' + gl.getProgramParameter( program, GL.VALIDATE_STATUS ) );
            onError( ''+gl.getError() );
			return;
		}
		screenProgram = program;
		gl.useProgram( screenProgram );

		cacheUniformLocation( program, 'resolution' );
		cacheUniformLocation( program, 'texture' );

		screenVertexPosition = gl.getAttribLocation( screenProgram, "position" );
		gl.enableVertexAttribArray( screenVertexPosition );
    }

    function createShader( src : String, type : Int ) : Shader {
        var shader = gl.createShader( type );
        gl.shaderSource( shader, src );
		gl.compileShader( shader );
        if( !gl.getShaderParameter( shader, GL.COMPILE_STATUS ) ) {
            var error = gl.getShaderInfoLog( shader );
			// Remove trailing linefeed, for FireFox's benefit.
			while( (error.length > 1) && (error.charCodeAt(error.length - 1) < 32) ) {
				error = error.substring( 0, error.length - 1);
			}
            onError( error );
			return null;
		}
		return shader;
    }

    function createRenderTarget( width : Int, height : Int ) : RenderTarget {

        var target = {
            framebuffer : gl.createFramebuffer(),
    		renderbuffer : gl.createRenderbuffer(),
    		texture : gl.createTexture()
        };

        // Setup framebuffer
        gl.bindTexture( GL.TEXTURE_2D, target.texture );
		gl.texImage2D( GL.TEXTURE_2D, 0, GL.RGBA, width, height, 0, GL.RGBA, GL.UNSIGNED_BYTE, null );
		gl.texParameteri( GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE );
		gl.texParameteri( GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE );
		gl.texParameteri( GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.NEAREST );
		gl.texParameteri( GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.NEAREST );
		gl.bindFramebuffer( GL.FRAMEBUFFER, target.framebuffer );
		gl.framebufferTexture2D( GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, target.texture, 0 );

        // Setup renderbuffer
		gl.bindRenderbuffer( GL.RENDERBUFFER, target.renderbuffer );
		gl.renderbufferStorage( GL.RENDERBUFFER, GL.DEPTH_COMPONENT16, width, height );
		gl.framebufferRenderbuffer( GL.FRAMEBUFFER, GL.DEPTH_ATTACHMENT, GL.RENDERBUFFER, target.renderbuffer );

        // Cleanup
		gl.bindTexture( GL.TEXTURE_2D, null );
		gl.bindRenderbuffer( GL.RENDERBUFFER, null );
		gl.bindFramebuffer( GL.FRAMEBUFFER, null);

        return target;
    }

    function createRenderTargets() {
        frontTarget = createRenderTarget( parameters.screenWidth, parameters.screenHeight );
        backTarget = createRenderTarget( parameters.screenWidth, parameters.screenHeight );
    }

    function computeSurfaceCorners() {
		if( gl != null ) {
			surface.width = surface.height * parameters.screenWidth / parameters.screenHeight;
			var halfWidth = surface.width * 0.5;
            var halfHeight = surface.height * 0.5;
			gl.bindBuffer( GL.ARRAY_BUFFER, surface.buffer );
			gl.bufferData( GL.ARRAY_BUFFER, new Float32Array( [
				surface.centerX - halfWidth, surface.centerY - halfHeight,
				surface.centerX + halfWidth, surface.centerY - halfHeight,
				surface.centerX - halfWidth, surface.centerY + halfHeight,
				surface.centerX + halfWidth, surface.centerY - halfHeight,
				surface.centerX + halfWidth, surface.centerY + halfHeight,
				surface.centerX - halfWidth, surface.centerY + halfHeight ]
            ), GL.STATIC_DRAW );
		}
	}

}
