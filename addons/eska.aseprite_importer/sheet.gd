# Copyright (c) eska <eska@eska.me>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

tool

class Cel:
	var position = Vector2()
	var region_rect = Rect2()
	var duration = 0

const FORMAT_HASH = 0
const FORMAT_ARRAY = 1

var _loaded = false
var _dict = {}
var _filenameRegex = RegEx.new()
var _format
var _texture_filename
var _texture_size
var _layers = []
var _frames = []
var _animations = null
var _anchor = Vector2()

var _error_message = "No error message available"

func _init():
	_filenameRegex.compile('(?<sprite>[^ ]+)( \\((?<layer>.+)\\))?( (?<index>\\d+))?')

func set_anchor(anchor):
	_anchor = anchor

func get_error_message():
	return _error_message

const ERRMSG_INVALID_JSON =\
"""Sheet JSON is not valid JSON"""
const ERRMSG_MISSING_KEY_STRF =\
"""Missing key "%s" in sheet"""
const ERRMSG_MISSING_VALUE_STRF =\
"""Missing value for key "%s" """
const ERRMSG_INVALID_KEY_STRF =\
"""Invalid key: "%s" """
const ERRMSG_INVALID_VALUE_STRF =\
"""Invalid value for key "%s" """

func is_loaded():
	return _loaded

func get_texture_filename():
	return _texture_filename

func get_texture_size():
	return _texture_size

func get_layers():
	return _layers

func get_frames():
	return _frames

func get_frame( frame_index ):
	return _frames[frame_index]

func get_frame_count():
	return _frames.size()

func is_animations_enabled():
	# type nil otherwise
	return typeof(_animations) == TYPE_DICTIONARY

func get_animation_names():
	return _animations.keys()

func get_animation( anim_name ):
	var frames = []
	for i in _animations[anim_name]:
		frames.push_back( get_frame( i ))
	return frames

func get_animation_length( anim_name ):
	var length = 0
	for frame_index in _animations[anim_name]:
		length += get_frame( frame_index )[0].duration
	return length

func get_animation_count():
	return _animations.size()

func get_format():
	return _format

func parse_json( json ):
	_dict = parse_json( json )
	if typeof(_dict) != TYPE_DICTIONARY:
		_error_message = ERRMSG_INVALID_JSON
		return FAILED
	var error = _initialize()
	return error

func _initialize():
	var error = _validate_base()
	if error != OK:
		return error
	error = _parse_meta()
	if error != OK:
		return error
	error = _determine_format()
	if error != OK:
		return error
	if get_format() == FORMAT_HASH:
		error = _parse_frames_dict( _dict.frames )
	elif get_format() == FORMAT_ARRAY:
		error = _parse_frames_array( _dict.frames )
	else: assert( false )
	if error != OK:
		return error
	if is_animations_enabled():
		error = _parse_animations()
		if error != OK:
			return error
	for i in _frames.size():
		var duration = 0
		for cel in _frames[i]:
			if cel.duration > 0:
				duration = cel.duration
				for cel in _frames[i]:
					cel.duration = duration
				break
		_grow_frame(i, duration)
	_loaded = true
	return OK

static func make_vector2( dict ):
	if dict.has('w') and dict.has('h'):
		return Vector2( dict.w, dict.h )

static func make_rect2( dict ):
	if dict.has('w') and dict.has('h') and dict.has('x') and dict.has('y'):
		return Rect2( dict.x, dict.y, dict.w, dict.h )

func _parse_meta():
	var meta = _dict.meta
	_texture_filename = meta.image.get_file()
	_texture_size = make_vector2( meta.size )
	## \TODO meta.scale
	if meta.has('frameTags'):
		_animations = {}
	return OK

func _determine_format():
	var type = typeof(_dict.frames)
	if type == TYPE_DICTIONARY:
		_format = FORMAT_HASH
		return OK
	elif type == TYPE_ARRAY:
		_format = FORMAT_ARRAY
		return OK
	_error_message = ERRMSG_INVALID_VALUE_STRF % 'frames'
	return ERR_INVALID_DATA

func _parse_frames_dict( frames ):
	for key in frames:
		frames[key]['filename'] = key
	var error = _parse_frames_array( frames.values() )
	if error != OK:
		return error
	return OK
	
func _parse_frames_array( array ):
	var error
	for frame in array:
		error = _validate_frame( frame )
		if error != OK:
			return error
		error = _parse_frame( frame )
		if error != OK:
			return error
	return OK

func _grow_frames(newsize):
	while _frames.size() < newsize:
		var frame = []
		while frame.size() < _layers.size():
			frame.append(Cel.new())
		_frames.append(frame)

func _grow_frame(i, duration):
	if i < 0:
		return
	if i >= _frames.size():
		_grow_frames(i+1)
		return
	var frame = _frames[i]
	while frame.size() < _layers.size():
		frame.append(Cel.new())
		frame.back().duration = duration

func _parse_frame( sheet_frame ):
	var regex_result = _filenameRegex.search(sheet_frame.filename)
	var index = regex_result.get_string('index')
	var layerindex = 0
	var layername = regex_result.get_string('layer')
	if layername != '':
		if _layers.size() == 0 or layername != _layers.back().name:
			if _dict.meta.has('layers'):
				_layers.append(_dict.meta.layers[_layers.size()])
			else:
				_layers.append({ 'name' : layername })
		layerindex = _layers.size()-1
	elif _layers.size() == 0:
		_layers.append({})
	index = index.to_int() if index.is_valid_integer() else 0

	_grow_frames(index + 1)
	_grow_frame(index, sheet_frame.duration)
	
	var frame = _frames[index]
	var cel = frame[layerindex]
	var rect = sheet_frame.frame
	var spriteSourceSize = sheet_frame.spriteSourceSize
	cel.position = Vector2(spriteSourceSize.x, spriteSourceSize.y)
	cel.region_rect = Rect2( rect.x, rect.y, rect.w, rect.h )
	var sourceSize = sheet_frame.sourceSize
	var anchor_offset = Vector2(sourceSize.w*_anchor.x, sourceSize.h*_anchor.y)
	cel.position -= anchor_offset
	cel.duration = sheet_frame.duration
	return OK

const DIRECTION_FORWARD = 'forward'
const DIRECTION_REVERSE = 'reverse'
const DIRECTION_PINGPONG = 'pingpong'

func _parse_animations():
	var error
	var maxframe = 0
	for animation in _dict.meta.frameTags:
		error = _validate_animation( animation )
		if error != OK:
			return error
		var sequence = []
		if animation.direction == DIRECTION_FORWARD or animation.direction == DIRECTION_PINGPONG:
			for frame_index in range( animation.from, animation.to+1 ):
				sequence.push_back( frame_index )
		if animation.direction == DIRECTION_REVERSE or animation.direction == DIRECTION_PINGPONG:
			for frame_index in range( animation.to-1, animation.from, -1 ):
				sequence.push_back( frame_index )
		_animations[animation.name] = sequence
		if animation.direction == DIRECTION_REVERSE:
			sequence.push_front( animation.to )
			sequence.push_back( animation.from )
		
		maxframe = max(maxframe, max(animation.from, animation.to))
	_grow_frames(maxframe + 1)
	return OK

## \name Validation
## \{

func _validate_base():
	var errmsg = _get_value_error( _dict, 'frames', null )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	
	if _dict.frames.size() <= 0:
		_error_message = ERRMSG_MISSING_VALUE_STRF % 'frames'
		return ERR_INVALID_DATA
	
	errmsg = _get_value_error( _dict, 'meta', TYPE_DICTIONARY )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	
	errmsg = _get_value_error( _dict.meta, 'image', TYPE_STRING )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	
	errmsg = _get_value_error( _dict.meta, 'size', TYPE_DICTIONARY )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	
	if make_vector2( _dict.meta.size ) == null:
		_error_message = ERRMSG_INVALID_VALUE_STRF % 'meta.size'
		return ERR_INVALID_DATA
	return OK

func _validate_frame( frame ):
	var errmsg = _get_value_error( frame, 'filename', TYPE_STRING )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	errmsg = _get_value_error( frame, 'frame', TYPE_DICTIONARY )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	if make_rect2( frame.frame ) == null:
		_error_message = ERRMSG_INVALID_VALUE_STRF % 'frame'
		return ERR_INVALID_DATA
	errmsg = _get_value_error( frame, 'duration', TYPE_REAL )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	return OK

func _validate_animation( anim ):
	var errmsg = _get_value_error( anim, 'name', TYPE_STRING )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	
	errmsg = _get_value_error( anim, 'direction', TYPE_STRING )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	
	var direction_is_valid = false
	for direction in [DIRECTION_FORWARD, DIRECTION_REVERSE, DIRECTION_PINGPONG]:
		if anim.direction == direction:
			direction_is_valid = true
			break
	if not direction_is_valid:
		_error_message = ERRMSG_INVALID_VALUE_STRF % 'direction'
		return ERR_INVALID_DATA
	
	errmsg = _get_value_error( anim, 'from', TYPE_REAL )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	errmsg = _get_value_error( anim, 'to', TYPE_REAL )
	if errmsg:
		_error_message = errmsg
		return ERR_INVALID_DATA
	return OK

static func _get_value_error( dict, expected_key, expected_type ):
	if not dict.has( expected_key ):
		return ERRMSG_MISSING_KEY_STRF % expected_key
	if expected_type!=null and not typeof(dict[expected_key]) == expected_type:
		return ERRMSG_INVALID_VALUE_STRF % expected_key
	return false

## \}
