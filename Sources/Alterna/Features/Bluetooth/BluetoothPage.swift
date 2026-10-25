import SwiftUI

/// Página de Bluetooth, no estilo do módulo da Central de Controle.
struct BluetoothPage: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(bluetooth.isPoweredOn ? Color.blue : Color.white.opacity(0.15)))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bluetooth")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(bluetooth.isPoweredOn ? "Ligado" : "Desligado")
                        .font(.system(size: 11))
                        .foregroundStyle(IslandStyle.secondary)
                }
                Spacer()
                if bluetooth.isPoweredOn {
                    CapsuleButton(title: bluetooth.isScanning ? "Procurando…" : "Procurar",
                                  symbol: bluetooth.isScanning ? nil : "plus") {
                        bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                    }
                }
                Toggle("", isOn: Binding(get: { bluetooth.isPoweredOn }, set: { bluetooth.setPower($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(.blue)
            }

            if let message = bluetooth.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow.opacity(0.9))
                    .lineLimit(2)
            }

            if bluetooth.isPoweredOn {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !bluetooth.nearby.isEmpty || bluetooth.isScanning {
                            sectionTitle("Por perto")
                            if bluetooth.nearby.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Procurando dispositivos em modo de pareamento…")
                                        .font(.system(size: 11))
                                        .foregroundStyle(IslandStyle.tertiary)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                            }
                            ForEach(bluetooth.nearby) { device in
                                DeviceRow(device: device, actionTitle: "Parear") { bluetooth.pair(device) }
                            }
                        }

                        sectionTitle("Meus dispositivos")
                        if bluetooth.paired.isEmpty {
                            Text("Nenhum dispositivo pareado.")
                                .font(.system(size: 12))
                                .foregroundStyle(IslandStyle.tertiary)
                                .padding(.horizontal, 8)
                        }
                        ForEach(bluetooth.paired) { device in
                            DeviceRow(device: device,
                                      actionTitle: device.isConnected ? "Desconectar" : "Conectar") {
                                bluetooth.toggleConnection(device)
                            }
                        }

                        Button("Ajustes de Bluetooth…") { bluetooth.openSystemSettings() }
                            .buttonStyle(.plain)
                            .linkCursor()
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(IslandStyle.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                    }
                }
            } else {
                IslandEmptyState(symbol: "antenna.radiowaves.left.and.right.slash",
                                 title: "Bluetooth desligado",
                                 message: "Ligue para conectar fones, teclados, mouses e outros dispositivos.",
                                 buttonTitle: "Ligar") { bluetooth.setPower(true) }
            }
        }
        .onAppear { bluetooth.activate() }
        .onDisappear { if bluetooth.isScanning { bluetooth.stopScan() } }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(IslandStyle.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

private struct DeviceRow: View {
    let device: BluetoothDevice
    let actionTitle: String
    let action: () -> Void
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        HoverRow(action: nil) {
            HStack(spacing: 10) {
                Image(systemName: device.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(device.isConnected ? Color.white : IslandStyle.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(device.isConnected ? Color.blue : IslandStyle.card))
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(device.isConnected ? "Conectado" : (device.isPaired ? "Não conectado" : "Disponível para parear"))
                        .font(.system(size: 11))
                        .foregroundStyle(IslandStyle.tertiary)
                }
                Spacer()
                if bluetooth.busy.contains(device.id) {
                    ProgressView().controlSize(.small)
                } else {
                    CapsuleButton(title: actionTitle, action: action)
                }
            }
        }
    }
}
