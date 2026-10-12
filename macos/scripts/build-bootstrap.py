#!/usr/bin/env python3
"""Emit the three-call bootstrap in engine/MihonEngine.java without a full JDK.

The release includes a JRE but no javac. This fixed, linear JVM method needs no
stack-map frames. It is equivalent to compiling the adjacent Java source with
javac --release 8 -cp Suwayomi-Server.jar. No third-party bytecode is modified.
"""
import struct
import sys
from pathlib import Path

def u2(value):
    return struct.pack(">H", value)

def u4(value):
    return struct.pack(">I", value)

pool = []

def utf8(value):
    encoded = value.encode("utf-8")
    pool.append(b"\x01" + u2(len(encoded)) + encoded)
    return len(pool)

def entry(tag, *indices):
    pool.append(bytes([tag]) + b"".join(u2(i) for i in indices))
    return len(pool)

this_class = entry(7, utf8("MihonEngine"))
super_class = entry(7, utf8("java/lang/Object"))
main_name = utf8("main")
main_descriptor = utf8("([Ljava/lang/String;)V")
code_name = utf8("Code")
setup_class = entry(7, utf8("suwayomi/tachidesk/server/ServerSetupKt"))
void_descriptor = utf8("()V")
setup_signature = entry(12, utf8("applicationSetup"), void_descriptor)
setup_method = entry(10, setup_class, setup_signature)
javalin_class = entry(7, utf8("suwayomi/tachidesk/server/JavalinSetup"))
singleton_signature = entry(12, utf8("INSTANCE"), utf8("Lsuwayomi/tachidesk/server/JavalinSetup;"))
singleton_field = entry(9, javalin_class, singleton_signature)
server_signature = entry(12, utf8("javalinSetup"), void_descriptor)
server_method = entry(10, javalin_class, server_signature)

# invokestatic applicationSetup; getstatic INSTANCE; invokevirtual javalinSetup; return
instructions = b"\xb8" + u2(setup_method) + b"\xb2" + u2(singleton_field) + b"\xb6" + u2(server_method) + b"\xb1"
code = u2(1) + u2(1) + u4(len(instructions)) + instructions + u2(0) + u2(0)
method = u2(0x0009) + u2(main_name) + u2(main_descriptor) + u2(1) + u2(code_name) + u4(len(code)) + code
binary = b"\xca\xfe\xba\xbe" + u2(0) + u2(52) + u2(len(pool) + 1) + b"".join(pool)
binary += u2(0x0031) + u2(this_class) + u2(super_class) + u2(0) + u2(0) + u2(1) + method + u2(0)
Path(sys.argv[1]).write_bytes(binary)
