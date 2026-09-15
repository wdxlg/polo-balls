"""Fetch just the official Windows release template via verified ZIP ranges."""
import io,json,urllib.request,zipfile,pathlib,sys
URL='https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
SIZE=1281349702
class RangeReader(io.RawIOBase):
    def __init__(self): self.pos=0; self.cache={}
    def readable(self):return True
    def seekable(self):return True
    def tell(self):return self.pos
    def seek(self,off,whence=0):
        self.pos=off if whence==0 else self.pos+off if whence==1 else SIZE+off
        return self.pos
    def read(self,n=-1):
        if n<0:n=SIZE-self.pos
        if not n:return b''
        if n>1048576:
            chunks=[]
            remaining=n
            while remaining:
                chunk=self.read(min(remaining,1048576))
                chunks.append(chunk)
                remaining-=len(chunk)
            return b''.join(chunks)
        start=self.pos;end=min(SIZE,start+n)-1
        key=(start,end)
        if key not in self.cache:
            req=urllib.request.Request(URL,headers={'Range':f'bytes={start}-{end}','User-Agent':'Godot-performance-verification'})
            with urllib.request.urlopen(req,timeout=30) as response:
                if response.status!=206:raise RuntimeError('Server did not honor range; stopped to avoid full 1.28 GB download')
                data=response.read(n+1)
                if len(data)!=end-start+1:raise RuntimeError('Range size mismatch: requested=%s-%s received=%s header=%s' % (start,end,len(data),response.headers.get('Content-Range')))
            self.cache[key]=data
        self.pos=end+1
        return self.cache[key]
folder=pathlib.Path('.performance_tools')
folder.mkdir(exist_ok=True)
(folder/'.gdignore').write_text('')
try:
    with zipfile.ZipFile(RangeReader()) as z:
        matches=[x for x in z.namelist() if x.endswith('/windows_release_x86_64.exe')]
        if len(matches)!=1:raise RuntimeError('Expected one Windows x86-64 release template: '+str(matches))
        info=z.getinfo(matches[0]);print('RELEASE_ENTRY',info.filename,info.compress_size,info.file_size,flush=True)
        data=z.read(info) # zipfile checks the CRC before this returns.
        (folder/'godot_release.exe').write_bytes(data)
        import hashlib
        print('RELEASE_READY',len(data),hashlib.sha256(data).hexdigest(),flush=True)
except Exception as e:
    print('RELEASE_DOWNLOAD_FAILED',repr(e),flush=True)
    sys.exit(1)
