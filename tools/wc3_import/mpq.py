import ctypes, os, sys
from ctypes import c_void_p, c_char_p, c_uint32, byref, c_bool
import platform
_HERE = os.path.dirname(os.path.abspath(__file__))
# Нужна библиотека StormLib (https://github.com/ladislav-zezula/StormLib): StormLib.dll рядом со скриптом на Windows
_names = ['StormLib.dll', 'storm.dll'] if platform.system() == 'Windows' else ['libstorm.so', 'libstorm.so.9']
lib = None
for _n in _names:
    for _p in (os.path.join(_HERE, _n), _n):
        try:
            lib = ctypes.CDLL(_p)
            break
        except OSError:
            pass
    if lib:
        break
if lib is None:
    raise OSError('Не найдена StormLib (%s). Скачайте/соберите её и положите рядом с mpq.py.' % ', '.join(_names))
lib.SFileOpenArchive.argtypes=[c_char_p,c_uint32,c_uint32,ctypes.POINTER(c_void_p)]
lib.SFileOpenArchive.restype=c_bool
lib.SFileOpenFileEx.argtypes=[c_void_p,c_char_p,c_uint32,ctypes.POINTER(c_void_p)]
lib.SFileOpenFileEx.restype=c_bool
lib.SFileGetFileSize.argtypes=[c_void_p,ctypes.POINTER(c_uint32)]
lib.SFileGetFileSize.restype=c_uint32
lib.SFileReadFile.argtypes=[c_void_p,c_void_p,c_uint32,ctypes.POINTER(c_uint32),c_void_p]
lib.SFileReadFile.restype=c_bool
lib.SFileCloseFile.argtypes=[c_void_p]
lib.SFileHasFile.argtypes=[c_void_p,c_char_p]; lib.SFileHasFile.restype=c_bool
class SFILE_FIND_DATA(ctypes.Structure):
    _fields_=[('cFileName',ctypes.c_char*1024),('szPlainName',c_char_p),('dwHashIndex',c_uint32),('dwBlockIndex',c_uint32),('dwFileSize',c_uint32),('dwFileFlags',c_uint32),('dwCompSize',c_uint32),('dwFileTimeLo',c_uint32),('dwFileTimeHi',c_uint32),('lcLocale',c_uint32)]
lib.SFileFindFirstFile.argtypes=[c_void_p,c_char_p,ctypes.POINTER(SFILE_FIND_DATA),c_char_p]
lib.SFileFindFirstFile.restype=c_void_p
lib.SFileFindNextFile.argtypes=[c_void_p,ctypes.POINTER(SFILE_FIND_DATA)]
lib.SFileFindNextFile.restype=c_bool
lib.SFileAddListFile.argtypes=[c_void_p,c_char_p]

class MPQ:
    def __init__(self,path,flags=0x100):  # STREAM_FLAG_READ_ONLY
        self.h=c_void_p()
        if not lib.SFileOpenArchive(path.encode(),0,flags,byref(self.h)):
            raise OSError('open failed %d'%ctypes.get_errno())
    def has(self,name): return lib.SFileHasFile(self.h,name.encode('latin1'))
    def read(self,name):
        fh=c_void_p()
        if not lib.SFileOpenFileEx(self.h,name.encode('latin1'),0,byref(fh)): return None
        hi=c_uint32(); size=lib.SFileGetFileSize(fh,byref(hi))
        buf=ctypes.create_string_buffer(size); got=c_uint32()
        lib.SFileReadFile(fh,buf,size,byref(got),None); lib.SFileCloseFile(fh)
        return buf.raw[:got.value]
    def addlist(self,path): return lib.SFileAddListFile(self.h,path.encode())
    def listing(self,mask='*'):
        fd=SFILE_FIND_DATA(); out=[]
        hf=lib.SFileFindFirstFile(self.h,mask.encode(),byref(fd),None)
        if not hf: return out
        while True:
            out.append((fd.cFileName.decode('latin1'),fd.dwFileSize))
            if not lib.SFileFindNextFile(hf,byref(fd)): break
        return out
