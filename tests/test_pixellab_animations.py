import importlib.util
import tempfile
import unittest
from pathlib import Path
from PIL import Image

spec=importlib.util.spec_from_file_location('generator',Path(__file__).parents[1]/'scripts/pixellab_animations.py')
g=importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)

class AnimationAssetsTest(unittest.TestCase):
    def test_png_transport_preserves_alpha(self):
        original=Image.new('RGBA',(96,96))
        original.putpixel((48,70),(20,80,30,255))
        result=g.decode_image(g.encode_image(original))
        self.assertEqual(result.tobytes(),original.tobytes())

    def test_strip_retains_frame_order_and_fixed_anchor(self):
        frames=[]
        for n in range(8):
            im=Image.new('RGBA',(96,96));im.putpixel((48,90),(n*20,100,80,255));frames.append(im)
        sheet=g.build_sheet(frames)
        self.assertEqual(sheet.size,(768,96))
        for n in range(8):self.assertEqual(sheet.getpixel((96*n+48,90)),(n*20,100,80,255))

    def test_v3_input_frame_is_not_part_of_animation(self):
        im=Image.new('RGBA',(96,96));im.putpixel((40,90),(1,2,3,255))
        frames=[im]*9
        self.assertEqual(g.build_sheet(frames).size,(768,96))

    def test_rejects_incomplete_or_opaque_generation(self):
        with self.assertRaises(RuntimeError):g.build_sheet([Image.new('RGBA',(96,96))]*7)
        with self.assertRaises(RuntimeError):g.build_sheet([Image.new('RGBA',(96,96),'white')]*8)

    def test_source_directions_share_canvas(self):
        sheet=Image.open('public/assets/player/operator-directions.png').convert('RGBA')
        for n in range(8):
            frame=g.source_frame(sheet,n)
            self.assertEqual(frame.size,(512,512))
            self.assertIsNotNone(frame.getchannel('A').getbbox())

if __name__=='__main__':unittest.main()
