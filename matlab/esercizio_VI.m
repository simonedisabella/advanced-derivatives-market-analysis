clear; 
close all; 
clc;

% Lettura dati
EURIBOR = readtable('EURIBOR3M.xlsx','Sheet','Price History');
EURIBOR = EURIBOR(:, {'Date','TotalReturn_Gross_'});
EURIBOR = sortrows(EURIBOR,'Date');
tasso_EURIBOR = EURIBOR.TotalReturn_Gross_;
tasso_EURIBOR = fillmissing(tasso_EURIBOR,'previous');
% Rimuovi eventuali NaN residui
tasso_EURIBOR = tasso_EURIBOR(isfinite(tasso_EURIBOR));

% Calcolo rendimenti semplici e logaritmici
rendimenti_semplici = tasso_EURIBOR(2:end) - tasso_EURIBOR(1:end-1);
if any(tasso_EURIBOR <= 0)                                                 
    error('Non posso calcolare log-rendimenti: ci sono valori del tasso_EURIBOR <= 0.');
end
rendimenti_logaritmici = log(tasso_EURIBOR(2:end)) - log(tasso_EURIBOR(1:end-1));

% Grafici
% Densità (Normale e Variance Gamma) e Istogramma empirico: rendimenti semplici
figure;
risultati_rendimenti_semplici = stima_e_plot_densita(gca, rendimenti_semplici, 'Rendimenti semplici: empirica vs Normale vs Variance Gamma');
% Densità (Normale e Variance Gamma) e Istogramma empirico: rendimenti logaritmici
figure;
risultati_rendimenti_logaritmici = stima_e_plot_densita(gca, rendimenti_logaritmici, 'Rendimenti logaritmici: empirica vs Normale vs Variance Gamma');
% QQ-plot: rendimenti semplici
figure;
qqplot(rendimenti_semplici);
grid on;
title('QQ-plot vs Normale (rendimenti semplici)');
% QQ-plot: log-rendimenti
figure;
qqplot(rendimenti_logaritmici);
grid on;
title('QQ-plot vs Normale (log-rendimenti)');

fprintf('\n- Rendimenti semplici: \n');
fprintf('  Normale: mu = %.6g  sigma = %.6g\n', risultati_rendimenti_semplici.mu_Normale, risultati_rendimenti_semplici.sigma_Normale);
fprintf('  Variance Gamma: m0 = %.6g  drift = %.6g  sigma = %.6g  shape = %.6g\n', risultati_rendimenti_semplici.parametri_Variance_Gamma(1), risultati_rendimenti_semplici.parametri_Variance_Gamma(2), risultati_rendimenti_semplici.parametri_Variance_Gamma(3), risultati_rendimenti_semplici.parametri_Variance_Gamma(4));
fprintf('  Kolmogorov–Smirnov (su z-score): h = %d  p = %.4g | Jarque–Bera: h = %d\n', risultati_rendimenti_semplici.esito_KolmogorovSmirnov, risultati_rendimenti_semplici.pvalue_KolmogorovSmirnov, risultati_rendimenti_semplici.esito_JarqueBera);
fprintf('\n- Log-rendimenti: \n');
fprintf('  Normale: mu = %.6g  sigma = %.6g\n', risultati_rendimenti_logaritmici.mu_Normale, risultati_rendimenti_logaritmici.sigma_Normale);
fprintf('  Variance Gamma: m0 = %.6g  drift = %.6g  sigma = %.6g  shape = %.6g\n', risultati_rendimenti_logaritmici.parametri_Variance_Gamma(1), risultati_rendimenti_logaritmici.parametri_Variance_Gamma(2), risultati_rendimenti_logaritmici.parametri_Variance_Gamma(3), risultati_rendimenti_logaritmici.parametri_Variance_Gamma(4));
fprintf('  Kolmogorov–Smirnov (su z-score): h = %d  p = %.4g | Jarque–Bera: h = %d\n', risultati_rendimenti_logaritmici.esito_KolmogorovSmirnov, risultati_rendimenti_logaritmici.pvalue_KolmogorovSmirnov, risultati_rendimenti_logaritmici.esito_JarqueBera);

%% Funzioni utilizzate 
function risultato = stima_e_plot_densita(asse_grafico_corrente, rendimenti, titoloPannello)
    rendimenti = rendimenti(:);
    rendimenti = rendimenti(isfinite(rendimenti));
    % Fit Normale
    [mu_Normale, sigma_Normale] = normfit(rendimenti);
    % Fit Variance Gamma tramite Stima per Massima VeroSimiglianza (x = [m0, drift, sigma, shape])
    parametri_partenza = [mean(rendimenti), 0, std(rendimenti), 1.2];       % 0 = senza asimmetria; 1.2 = forma moderata e numericamente stabile
    vincolo_inferiore = [-Inf, -Inf, 1e-8, 1e-8];
    vincolo_superiore = [ Inf,  Inf,  Inf,  Inf];
    opzioni_ottimizzate = optimoptions('fmincon', 'Display','off', 'Algorithm','interior-point', 'MaxFunctionEvaluations', 2e5, 'MaxIterations', 2e4);
    parametri_Variance_Gamma = fmincon(@(x) -log_verosimiglianza_VarianceGamma(rendimenti, x), parametri_partenza, [],[],[],[], vincolo_inferiore, vincolo_superiore, [], opzioni_ottimizzate);
    % Griglia robusta (per far vedere bene anche la Variance Gamma)
    quantile = prctile(rendimenti, [0.5 99.5]);
    margine = 0.15*(quantile(2)-quantile(1) + eps);
    x_minimo = quantile(1) - margine;
    x_massimo = quantile(2) + margine;
    griglia = linspace(x_minimo, x_massimo, 800);
    densita_Normale = normpdf(griglia, mu_Normale, sigma_Normale);
    densita_Variance_Gamma = densita_pdf_VarianceGamma(griglia, parametri_Variance_Gamma);
    densita_Variance_Gamma(~isfinite(densita_Variance_Gamma) | densita_Variance_Gamma<0) = 0;
    cla(asse_grafico_corrente);
    histogram(asse_grafico_corrente, rendimenti, 30, 'Normalization','pdf', 'DisplayName','Empirica');
    hold(asse_grafico_corrente, 'on');
    plot(asse_grafico_corrente, griglia, densita_Variance_Gamma, 'LineWidth', 2, 'DisplayName', 'Variance Gamma');
    plot(asse_grafico_corrente, griglia, densita_Normale, 'LineWidth', 2, 'DisplayName', 'Normale');
    legend(asse_grafico_corrente,'Location','best');
    grid(asse_grafico_corrente,'on');
    title(asse_grafico_corrente, titoloPannello);
    hold(asse_grafico_corrente,'off');
    % Diagnostica
    z = (rendimenti - mu_Normale) / sigma_Normale;
    [esito_KolmogorovSmirnov, pvalue_KolmogorovSmirnov] = kstest(z);
    esito_JarqueBera = jbtest(rendimenti);
    risultato.mu_Normale = mu_Normale;
    risultato.sigma_Normale = sigma_Normale;
    risultato.parametri_Variance_Gamma = parametri_Variance_Gamma;
    risultato.esito_KolmogorovSmirnov = esito_KolmogorovSmirnov;
    risultato.pvalue_KolmogorovSmirnov = pvalue_KolmogorovSmirnov;
    risultato.esito_JarqueBera = esito_JarqueBera;
end

function log_verosimiglianza = log_verosimiglianza_VarianceGamma(y, par)
    log_densita = logdensita_pdf_VarianceGamma(y, par);
    if any(~isfinite(log_densita))
        log_verosimiglianza = -Inf;
    else
        log_verosimiglianza = sum(log_densita);
    end
end

function pdf = densita_pdf_VarianceGamma(x, par)
    pdf = exp(logdensita_pdf_VarianceGamma(x, par));
end

function log_densita_VarianceGamma = logdensita_pdf_VarianceGamma(x, par)
    % Parametri: par = [m0, drift, sigma, shape]
    m0 = par(1);
    drift = par(2);
    sigma = par(3);
    shape = par(4);
    x = x(:);
    dy = abs(x - m0) + 1e-12;
    Z = sqrt(2*sigma^2 + drift^2) .* dy ./ (sigma^2);
    nu = shape - 1/2;
    % Bessel K scalata (stabile numericamente)
    bessel_K_scalata = besselk(nu, Z, 1);
    bessel_K_scalata = max(bessel_K_scalata, 1e-300);
    termine_costante_logaritmo = 0.5*log(2) - log(gamma(shape)) - log(sigma) - 0.5*log(pi);
    termine_asimmetria_logaritmo = ((x - m0) * drift) / (sigma^2);
    termine_potenza_logaritmo = (shape - 0.5) * (log(dy) - 0.5*log(drift^2 + 2*sigma^2));
    termine_bessel_logaritmo = log(bessel_K_scalata) - Z;
    log_densita_VarianceGamma = termine_costante_logaritmo + termine_asimmetria_logaritmo + termine_potenza_logaritmo + termine_bessel_logaritmo;
end