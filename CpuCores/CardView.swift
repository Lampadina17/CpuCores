//
//  CardView.swift
//  CpuCores
//
//  Created by Lampadina_17 on 05/10/22.
//

import SwiftUI

struct Gauge: View {
    
    var title:String    // Titolo
    var value:Double       // Valore
    var buttonHandler: (()->())?
    
    init(title:String, value:Double, buttonHandler: (()->())?) {
        self.title = title
        self.value = value
        self.buttonHandler = buttonHandler
    }
    
    var body: some View {
        let usage = String(value);
        VStack(alignment: .center, spacing: 0) {
            HStack {
                Text(title + ": ").foregroundColor(.black).padding()
                Text(usage + "%").foregroundColor(.black).padding()
            }
        }
        .background(Color.white)
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
    var valueName: String
    var capsuleColor: ColorRGB
    var body: some View {
        VStack {
            Text("\(value)")
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.gray)
                    .opacity(0.1)
                    .frame(width: width, height: 400)
                Capsule()
                    .fill(Color(.sRGB, red: capsuleColor.red, green: capsuleColor.green, blue: capsuleColor.blue))
                    .frame(width: width, height: CGFloat(value) / CGFloat(maxValue) * 400)
                    .animation(.easeOut(duration: 0.5))
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
