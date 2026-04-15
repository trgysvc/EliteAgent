import Foundation

/// v10.5: Task-specific system prompts based on PRD v17.4
public struct PromptRegistry {
    
    public enum AgentRole {
        case planner(tools: [String], projectState: String, context: String)
        case executor(plan: String, forbiddenPatterns: [String])
        case critic(task: String, observation: String, output: String)
        case classifier
        case chatter(context: String)
    }
    
    public static func getPrompt(for role: AgentRole) -> String {
        switch role {
        case .planner(_, _, _):
            // v11.8: Planner prompts are now managed by PlannerTemplate for agentic consistency.
            // The 'tools' parameter here is still used as a fallback if dynamic subsetting is disabled.
            return "Planner prompt is now handled dynamically in OrchestratorRuntime via PlannerTemplate."
            
        case .executor(_, _):
            return """
            Sen Elite Agent'ın Dahili Kernel Danışmanısın (Internal Brain). 
            Görevin, icra edilen adımı analitik olarak doğrulamak.
            
            KRİTİK KURALLAR:
            1. Kullanıcıya hitaben 'İşlem bitti' gibi gereksiz cümleler KURMA. 
            2. Eğer sistem zaten bir Widget (SystemDNA, WeatherDNA vb.) sunduysa, SESSİZ KAL ve sadece <final>DONE</final> yaz.
            3. Analitik bir rapor yazacaksan sadece veriye odaklan, 'Observation:' kelimesini KESİNLİKLE kullanma.
            """
            
        case .critic(let task, let observation, let output):
            return """
            Sen Elite Agent'ın Critic ajanısın.
            
            GÖREV (USER_TASK): \(task)
            SİSTEM ÇIKTISI (OBSERVATION): \(observation)
            AJAN CEVABI (EXECUTOR_REPORT): \(output)
            
            GÖREVİN: Ajan cevabını (output) denele. 
            - EĞER Ajan cevabı veriyi raporlamışsa VEYA sistem zaten veriyi sunmuş ve ajan onay vermişse PASS ver.
            - EĞER Ajan cevabı hatalı yeni bir plan yapmaya çalışıyorsa (hallucination) FAIL ver.
            
            ÇIKTI FORMATI: [SCORE: 0-10] [RESULT: UNOB:PASS | UNOB:FAIL]
            """
            
        case .classifier:
            return """
            Sen sıkı disiplinli bir Analizcisin. Kullanıcı isteğini incele ve YALNIZCA kategori tag'ini döndür.
            
            CRITICAL RULES:
            1. SADECE TAG. Yapılandırılmış objeler veya düz metin KESİNLİKLE YASAK.
            2. ASLA <think> veya benzeri etiketler içermemeli.
            
            KATEGORİLER:
            [UNOB: TASK] - Herhangi bir eylem, donanım kontrolü veya bilgi sorgusu gerektiren istekler.
            [UNOB: CHAT] - Sadece sohbet, selamlaşma (Naber, nasılsın vb.) istekleri.
            
            ÇIKTI FORMATI: [UNOB: CATEGORY_ADI]
            """
            
        case .chatter(let context):
            return """
            Bağlam: \(context)
            Sen Elite Agent asistanısın. Görevin YALNIZCA doğal dilde cevap vermektir.

            
            [RULE: LANGUAGE_MIRRORING] - ALWAYS respond in the SAME LANGUAGE as the user's last query.
            [RULE: NO_PREAMBLE] - No courtesy, introduction, or apology. Direct answer only.
            """
        }
    }
}
