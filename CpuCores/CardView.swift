//
//  CardView.swift
//  CpuCores
//
//  Created by Lampadina_17 on 05/10/22.
//

import SwiftUI

struct MyButton: View {
    
    var title:String // Titolo
    
    init(title: String) {
        self.title = title
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Button(action: {
                print("outer button pressed")
            }) {
                Text(title)
                    .foregroundColor(.black)
                    .padding()
                    .clipShape(RoundedRectangle(cornerRadius: 15.0, style: .continuous))
            }
        }
        .background(Color.white)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.2), radius: 7, x: 0, y: 2)
    }
}

struct Gauge: View {
    
    var title:String // Titolo
    var value:String // Valore
    
    init(title:String, value:String) {
        self.title = title
        self.value = value
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack {
                Text(title + ": ").foregroundColor(.white).padding()
                Text(value).foregroundColor(.white).padding()
            }
        }
        .background(Color.white.opacity(0.3))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.2), radius: 7, x: 0, y: 2)
    }
}
/*
 struct ProductCard_Previews: PreviewProvider {
 static var previews: some View {
 Gauge(title: "CPU Usage", value: 9, buttonHandler: nil)
 }
 }*/

struct RoundedCorners: Shape {
    var tl: CGFloat = 0.0
    var tr: CGFloat = 0.0
    var bl: CGFloat = 0.0
    var br: CGFloat = 0.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.size.width
        let h = rect.size.height
        
        let tr = min(min(self.tr, h/2), w/2)
        let tl = min(min(self.tl, h/2), w/2)
        let bl = min(min(self.bl, h/2), w/2)
        let br = min(min(self.br, h/2), w/2)
        
        path.move(to: CGPoint(x: w / 2.0, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr,
                    startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br,
                    startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl,
                    startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl,
                    startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        return path
    }
}

struct CapsuleBar: View {
    var value: Int
    var maxValue: Int
    var width: CGFloat
    var height: CGFloat
    var valueName: String
    var capsuleColor: ColorRGB
    var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white)
                    .opacity(0.5)
                    .frame(width: width, height: height)
                Capsule()
                    .fill(Color(.sRGB, red: capsuleColor.red, green: capsuleColor.green, blue: capsuleColor.blue))
                    .frame(width: width, height: CGFloat(value) / CGFloat(maxValue) * height)
            }
            Text("\(valueName)")
        }
    }
}

struct ColorRGB {
    var red: Double
    var green: Double
    var blue: Double
}
