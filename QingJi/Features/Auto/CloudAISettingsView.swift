import SwiftUI

/// 云端智能抽取配置（用户自带 API Key，默认关闭；文档 F-12 语义层云端档）
struct CloudAISettingsView: View {
    @State private var config = CloudAIStore.load()
    @State private var selectedPreset = "deepseek"
    @State private var showSavedHint = false

    var body: some View {
        Form {
            Section {
                Toggle("启用云端抽取", isOn: $config.enabled)
            } footer: {
                Text("默认关闭。启用后，截图识别的 OCR 文本会发送到你配置的服务商做语义抽取（金额/时间/商户/备注更准）。端侧大模型可用时优先走端侧，云端作为其不可用时的备选或增强。")
            }

            Section("服务商") {
                Picker("预设", selection: $selectedPreset) {
                    ForEach(CloudExtractionService.presets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                    Text("自定义").tag("custom")
                }
                .onChange(of: selectedPreset) { _, newValue in
                    if let preset = CloudExtractionService.presets.first(where: { $0.id == newValue }) {
                        config.baseURL = preset.baseURL
                        config.model = preset.model
                    }
                }
                if let preset = CloudExtractionService.presets.first(where: { $0.id == selectedPreset }) {
                    Text(preset.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("接口配置") {
                TextField("Base URL", text: $config.baseURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.caption)
                SecureField("API Key", text: $config.apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("模型名", text: $config.model)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section {
                Button("保存配置") {
                    CloudAIStore.save(config)
                    showSavedHint = true
                }
                .disabled(config.apiKey.trimmingCharacters(in: .whitespaces).isEmpty && config.enabled)
            } footer: {
                Text("API Key 仅保存在本机。国内服务商可直连，无需代理。")
            }

            if showSavedHint {
                Section {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.income)
                }
            }
        }
        .navigationTitle("云端智能抽取")
        .onAppear {
            selectedPreset = CloudExtractionService.presets.first(where: { $0.baseURL == config.baseURL && $0.model == config.model })?.id ?? "custom"
        }
    }
}
