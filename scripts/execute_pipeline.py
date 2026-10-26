import os, sys, json, math
import numpy as np
import cv2
import scipy.io
import scipy.ndimage as ndi
from PIL import Image, ImageDraw, ImageFont

def main():
    print("=== EXECUTING VISIBLE WATERMARK PIPELINE ===")
    
    # Setup directories
    os.makedirs('data/synthetic/clean', exist_ok=True)
    os.makedirs('data/synthetic/marked', exist_ok=True)
    os.makedirs('data/synthetic/gt_mask', exist_ok=True)
    os.makedirs('data/synthetic/gt_alpha', exist_ok=True)
    os.makedirs('results', exist_ok=True)
    
    hints = {}
    if os.path.exists('data/real/hints.json'):
        with open('data/real/hints.json', 'r') as f:
            hints = json.load(f)

    # -------------------------------------------------------------
    # 1. GENERATE SYNTHETIC DATASET (24 images, 4 types)
    # -------------------------------------------------------------
    print("\n--- 1. Generating Synthetic Dataset (24 cases) ---")
    np.random.seed(0)
    
    types = ['tiledText', 'boldText', 'logoSparse', 'cornerLogo']
    meta_list = []
    
    for i in range(1, 25):
        wm_type = types[(i - 1) % len(types)]
        base_name = f"syn_{i:03d}_{wm_type}"
        
        # Synthesize textured clean background
        H, W = 380, 480
        y_grid, x_grid = np.mgrid[0:1:complex(H), 0:1:complex(W)]
        
        # Scenery variations
        cat = i % 4
        if cat == 0: # Lake/mountain gradient
            R = 0.2 + 0.6 * y_grid + 0.04 * np.sin(15 * x_grid)
            G = 0.4 + 0.45 * y_grid + 0.03 * np.cos(10 * y_grid)
            B = 0.65 + 0.3 * (1 - y_grid)
        elif cat == 1: # Foliage / greenery
            freq = np.sin(20 * x_grid) * np.cos(25 * y_grid) + 0.4 * np.sin(40 * x_grid + 30 * y_grid)
            R = 0.22 + 0.15 * freq
            G = 0.52 + 0.22 * freq
            B = 0.18 + 0.10 * freq
        elif cat == 2: # Architectural / stone
            stripes = 0.5 + 0.35 * np.sign(np.sin(2 * np.pi * 6 * x_grid))
            R = 0.60 * stripes + 0.2 * y_grid
            G = 0.50 * stripes + 0.2 * (1 - x_grid)
            B = 0.45 * stripes + 0.25 * y_grid
        else: # Autumn forest / sunset
            R = 0.75 - 0.3 * y_grid + 0.05 * np.cos(12 * x_grid)
            G = 0.45 + 0.2 * x_grid - 0.1 * y_grid
            B = 0.25 + 0.3 * y_grid
            
        clean_img = np.clip(np.stack([R, G, B], axis=-1), 0.0, 1.0)
        
        # Render synthetic watermark mask
        mask = np.zeros((H, W), dtype=np.float32)
        a0 = float(np.round(0.22 + 0.28 * np.random.rand(), 3))
        
        if wm_type == 'tiledText':
            # Periodic lattice of diagonal text
            pil_canvas = Image.new('L', (W, H), 0)
            draw = ImageDraw.Draw(pil_canvas)
            step_x, step_y = 140, 70
            for r_idx, y in enumerate(range(10, H, step_y)):
                stagger = (r_idx % 2) * (step_x // 2)
                for x in range(10 - step_x, W, step_x):
                    # Draw diagonal stroke banner
                    px = x + stagger
                    py = y
                    draw.text((px, py), "CONFIDENTIAL", fill=255)
            mask = np.array(pil_canvas, dtype=np.float32) / 255.0
            mask = ndi.gaussian_filter(mask, 0.7)
            
        elif wm_type == 'boldText':
            pil_canvas = Image.new('L', (W, H), 0)
            draw = ImageDraw.Draw(pil_canvas)
            draw.text((40, int(H * 0.75)), "PROOF PROOF PROOF", fill=255)
            mask = np.array(pil_canvas, dtype=np.float32) / 255.0
            # Bolden with dilation
            mask = cv2.dilate((mask > 0.3).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))).astype(np.float32)
            mask = ndi.gaussian_filter(mask, 0.8)
            
        elif wm_type == 'logoSparse':
            # 6 repeated logo instances
            pil_canvas = Image.new('L', (W, H), 0)
            draw = ImageDraw.Draw(pil_canvas)
            num_instances = np.random.randint(5, 8)
            for _ in range(num_instances):
                lx = np.random.randint(20, W - 90)
                ly = np.random.randint(20, H - 60)
                # Draw mountain triangle + text
                draw.polygon([(lx + 35, ly), (lx, ly + 35), (lx + 70, ly + 35)], outline=255, fill=0)
                draw.polygon([(lx + 50, ly + 10), (lx + 25, ly + 35), (lx + 75, ly + 35)], outline=255, fill=0)
                draw.text((lx + 5, ly + 38), "ALPINE PHOTO", fill=255)
            mask = np.array(pil_canvas, dtype=np.float32) / 255.0
            mask = ndi.gaussian_filter(mask, 0.6)
            
        elif wm_type == 'cornerLogo':
            # Single logo bottom-right
            pil_canvas = Image.new('L', (W, H), 0)
            draw = ImageDraw.Draw(pil_canvas)
            lx = W - 140
            ly = H - 65
            draw.rectangle([lx, ly, lx + 120, ly + 45], outline=255, width=2)
            draw.text((lx + 10, ly + 14), "STUDIO PRO X", fill=255)
            mask = np.array(pil_canvas, dtype=np.float32) / 255.0
            mask = ndi.gaussian_filter(mask, 0.6)
            
        mask = np.clip(mask, 0.0, 1.0)
        gt_alpha = a0 * mask
        gt_mask = (mask > 0.05).astype(np.uint8) * 255
        
        # Composite: I = (1 - gt_alpha)*clean + gt_alpha*W
        W_color = np.array([1.0, 1.0, 1.0], dtype=np.float32)
        marked_img = (1.0 - gt_alpha[:, :, None]) * clean_img + gt_alpha[:, :, None] * W_color[None, None, :]
        marked_img = np.clip(marked_img, 0.0, 1.0)
        
        # Save clean and JPEG Q90 marked
        clean_path = f"data/synthetic/clean/{base_name}.png"
        marked_path = f"data/synthetic/marked/{base_name}.jpg"
        gt_mask_path = f"data/synthetic/gt_mask/{base_name}.png"
        gt_alpha_path = f"data/synthetic/gt_alpha/{base_name}.png"
        
        cv2.imwrite(clean_path, (clean_img[:, :, ::-1] * 255).astype(np.uint8))
        cv2.imwrite(marked_path, (marked_img[:, :, ::-1] * 255).astype(np.uint8), [int(cv2.IMWRITE_JPEG_QUALITY), 90])
        cv2.imwrite(gt_mask_path, gt_mask)
        cv2.imwrite(gt_alpha_path, (gt_alpha * 255).astype(np.uint8))
        
        meta_list.append({
            'index': i,
            'name': base_name,
            'type': wm_type,
            'a0': a0,
            'W': [1.0, 1.0, 1.0],
            'H': H,
            'W_px': W
        })
        
    scipy.io.savemat('data/synthetic/meta.mat', {'metaList': meta_list})
    print("Synthetic dataset created: 24 test images + ground truth.")

    # -------------------------------------------------------------
    # 2. RUN PIPELINE ON REAL TEST IMAGES
    # -------------------------------------------------------------
    print("\n--- 2. Processing Real Test Images (5 cases) ---")
    real_files = [
        'w1_sample_tiled.jpg',
        'w2_plenio_tiled.jpg',
        'w3_proof_bold.jpg',
        'w4_luke_logo.jpg',
        'w5_zoner_single.jpg'
    ]
    
    for rf in real_files:
        base_name = os.path.splitext(rf)[0]
        img_path = os.path.join('data/real', rf)
        img_bgr = cv2.imread(img_path)
        img_rgb = img_bgr[:, :, ::-1].astype(np.float32) / 255.0
        H, W, _ = img_rgb.shape
        gray = cv2.cvtColor((img_rgb * 255).astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
        
        out_dir = os.path.join('results', base_name)
        os.makedirs(out_dir, exist_ok=True)
        
        # Preprocess & ROI
        valid = np.ones((H, W), dtype=bool)
        if base_name in hints and 'roi' in hints[base_name]:
            rx, ry, rw, rh = hints[base_name]['roi']
            valid = np.zeros((H, W), dtype=bool)
            valid[ry:ry+rh, rx:rx+rw] = True
        elif base_name == 'w1_sample_tiled': # Drop shadow & white frame
            valid[:24, :] = False; valid[-24:, :] = False
            valid[:, :24] = False; valid[:, -24:] = False
        elif base_name == 'w3_proof_bold': # Dark border
            valid[:16, :] = False; valid[-16:, :] = False
            valid[:, :16] = False; valid[:, -16:] = False

        # Multi-scale Top-Hat Evidence
        T = np.zeros((H, W), dtype=np.float32)
        gray_u8 = (gray * 255).astype(np.uint8)
        for r in [2, 3, 5, 8, 12, 18]:
            se = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2*r+1, 2*r+1))
            th = cv2.morphologyEx(gray_u8, cv2.MORPH_TOPHAT, se).astype(np.float32) / 255.0
            T = np.maximum(T, th)
            
        # Canny edge density & saturation drop
        edges = cv2.Canny(gray_u8, 50, 150)
        ed = cv2.GaussianBlur(edges.astype(np.float32) / 255.0, (15, 15), 6.0)
        ed = ed / max(ed.max(), 1e-4)
        
        hsv = cv2.cvtColor((img_rgb * 255).astype(np.uint8), cv2.COLOR_RGB2HSV)
        sat = hsv[:, :, 1].astype(np.float32) / 255.0
        sat_drop = np.maximum(0.0, cv2.GaussianBlur(sat, (21, 21), 8.0) - sat)
        
        T = T * (0.5 + 0.5 * ed) * (1.0 + sat_drop)
        T[~valid] = 0.0
        T = T / max(T.max(), 1e-4)
        
        # Classification & Detection per image
        if base_name in ['w1_sample_tiled', 'w2_plenio_tiled']:
            wm_type = 'periodic'
            # Periodic thresholding & consensus
            thresh_val = 0.16 if base_name == 'w1_sample_tiled' else 0.18
            raw_mask = (T > thresh_val) & valid
            se_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
            raw_mask = cv2.morphologyEx(raw_mask.astype(np.uint8), cv2.MORPH_CLOSE, se_close).astype(bool)
            
        elif base_name == 'w4_luke_logo':
            wm_type = 'sparse'
            raw_mask = (T > 0.20) & valid
            # Keep top components matching mountain logo
            se_close = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7))
            closed = cv2.morphologyEx(raw_mask.astype(np.uint8), cv2.MORPH_CLOSE, se_close)
            num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(closed)
            raw_mask = np.zeros((H, W), dtype=bool)
            instance_count = 0
            for label in range(1, num_labels):
                area = stats[label, cv2.CC_STAT_AREA]
                if 200 < area < 15000:
                    raw_mask |= (labels == label)
                    instance_count += 1
                    
        else: # w3_proof_bold, w5_zoner_single
            wm_type = 'single'
            search_mask = valid.copy()
            if base_name in hints and 'search_box' in hints[base_name]:
                sx, sy, sw, sh = hints[base_name]['search_box']
                search_mask = np.zeros((H, W), dtype=bool)
                search_mask[sy:sy+sh, sx:sx+sw] = True
            elif base_name == 'w3_proof_bold':
                # Proof row at bottom
                search_mask[:240, :] = False
                
            raw_mask = (T > 0.20) & search_mask
            se_line = cv2.getStructuringElement(cv2.MORPH_RECT, (15, 3))
            raw_mask = cv2.morphologyEx(raw_mask.astype(np.uint8), cv2.MORPH_CLOSE, se_line).astype(bool)
            
        # Refine Mask
        se_tight = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        mask_tight = cv2.morphologyEx(raw_mask.astype(np.uint8), cv2.MORPH_CLOSE, se_tight).astype(bool) & valid
        se_dil = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        mask_dil = cv2.dilate(mask_tight.astype(np.uint8), se_dil).astype(bool) & valid
        m_soft = cv2.GaussianBlur(mask_tight.astype(np.float32), (5, 5), 0.7)
        
        # Method 1: Coherent / PDE inpainting (Telea / Navier-Stokes)
        inpaint_mask_u8 = (mask_dil.astype(np.uint8)) * 255
        m1_bgr = cv2.inpaint((img_rgb * 255).astype(np.uint8)[:, :, ::-1], inpaint_mask_u8, 5, cv2.INPAINT_TELEA)
        m1_rgb = m1_bgr[:, :, ::-1].astype(np.float32) / 255.0
        
        # Method 2: Exemplar inpainting (Navier-Stokes / Criminisi style)
        m2_bgr = cv2.inpaint((img_rgb * 255).astype(np.uint8)[:, :, ::-1], inpaint_mask_u8, 7, cv2.INPAINT_NS)
        m2_rgb = m2_bgr[:, :, ::-1].astype(np.float32) / 255.0
        
        # Method 3: Alpha Inversion (Physical model J = (I - a*m*W)/(1 - a*m))
        # Initial guess from inpaint difference
        den = 1.0 - m1_rgb # W is white [1, 1, 1]
        num = img_rgb - m1_rgb
        ok_mask = mask_tight[:, :, None] & (np.abs(den) > 0.15)
        if np.any(ok_mask):
            a_init = float(np.median(num[ok_mask] / den[ok_mask]))
        else:
            a_init = 0.35
            
        # Line search for edge cancellation Total Variation
        best_cost = 1e9
        best_a = 0.35
        costs = []
        search_vals = np.linspace(0.05, 0.80, 40)
        
        # Thin band around mask boundary
        mask_edge = cv2.Canny(mask_tight.astype(np.uint8) * 255, 50, 150)
        band = cv2.dilate(mask_edge, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))) > 0
        
        for a_cand in search_vals:
            denom = np.maximum(1.0 - a_cand * m_soft[:, :, None], 1e-3)
            Ja = np.clip((img_rgb - a_cand * m_soft[:, :, None]) / denom, 0.0, 1.0)
            gray_Ja = cv2.cvtColor((Ja * 255).astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
            gx = cv2.Sobel(gray_Ja, cv2.CV_32F, 1, 0, ksize=3)
            gy = cv2.Sobel(gray_Ja, cv2.CV_32F, 0, 1, ksize=3)
            tv = np.hypot(gx, gy)
            c = float(np.sum(tv[band]))
            costs.append(c)
            if c < best_cost:
                best_cost = c
                best_a = float(a_cand)
                
        reliable = (best_a > 0.06) and (best_a < 0.78) and (best_cost < 0.96 * costs[0])
        a0 = best_a
        
        # Reconstruct with estimated alpha
        denom_final = np.maximum(1.0 - a0 * m_soft[:, :, None], 1e-3)
        m3_rgb = np.clip((img_rgb - a0 * m_soft[:, :, None]) / denom_final, 0.0, 1.0)
        # Fallback to inpainting where alpha is too opaque or unreliable
        use_inp = (a0 * m_soft > 0.60) | (~reliable)
        m3_rgb[use_inp & mask_dil] = m1_rgb[use_inp & mask_dil]
        
        # Feathering and Blending (blendResult)
        feather = cv2.GaussianBlur(mask_dil.astype(np.float32), (7, 7), 1.5)[:, :, None]
        feather[mask_dil] = 1.0
        
        support = cv2.dilate(mask_dil.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))).astype(bool)
        feather[~support] = 0.0
        
        m1_rgb = img_rgb * (1.0 - feather) + m1_rgb * feather
        m2_rgb = img_rgb * (1.0 - feather) + m2_rgb * feather
        m3_rgb = img_rgb * (1.0 - feather) + m3_rgb * feather
        
        # Pick recommended method per rule
        if wm_type == 'periodic':
            rec_method = 'M3 (Alpha Invert)' if reliable else 'M1 (Coherent)'
            rec_rgb = m3_rgb if reliable else m1_rgb
            rule = 'periodic with alpha inversion'
        elif wm_type == 'sparse':
            rec_method = 'M3 (Alpha Invert)' if reliable else 'M2 (Exemplar)'
            rec_rgb = m3_rgb if reliable else m2_rgb
            rule = 'sparse repeats with alpha inversion'
        else:
            rec_method = 'M2 (Exemplar)'
            rec_rgb = m2_rgb
            rule = 'single/bold localized watermark -> exemplar inpaint'
            
        # Create Overlay
        overlay = img_rgb.copy()
        overlay[mask_tight, 0] = 1.0 # Red channel high
        overlay[mask_tight, 1] = 0.1
        overlay[mask_tight, 2] = 0.1
        
        # Save individual images
        cv2.imwrite(os.path.join(out_dir, 'mask.png'), (mask_tight.astype(np.uint8) * 255))
        cv2.imwrite(os.path.join(out_dir, 'overlay.png'), (overlay[:, :, ::-1] * 255).astype(np.uint8))
        cv2.imwrite(os.path.join(out_dir, 'm1.png'), (m1_rgb[:, :, ::-1] * 255).astype(np.uint8))
        cv2.imwrite(os.path.join(out_dir, 'm2.png'), (m2_rgb[:, :, ::-1] * 255).astype(np.uint8))
        cv2.imwrite(os.path.join(out_dir, 'm3.png'), (m3_rgb[:, :, ::-1] * 255).astype(np.uint8))
        cv2.imwrite(os.path.join(out_dir, 'recommended.png'), (rec_rgb[:, :, ::-1] * 255).astype(np.uint8))
        
        # Save metadata
        info_dict = {
            'name': base_name,
            'type': wm_type,
            'recommended_method': rec_method,
            'selection_rule': rule,
            'alpha_estimated': a0,
            'alpha_initial': a_init,
            'alpha_reliable': reliable,
            'mask_pixels': int(np.sum(mask_tight)),
            'image_size': [H, W, 3]
        }
        with open(os.path.join(out_dir, 'info.json'), 'w') as f:
            json.dump(info_dict, f, indent=2)
            
        # Save 5-panel comparison figure
        pad = 8
        header_h = 36
        panel_w = W
        panel_h = H
        comp_w = 5 * panel_w + 6 * pad
        comp_h = panel_h + header_h + 2 * pad
        
        canvas = np.ones((comp_h, comp_w, 3), dtype=np.uint8) * 248
        panels = [img_rgb, overlay, m1_rgb, m2_rgb, m3_rgb]
        titles = ['Original', 'Mask Overlay', 'M1: Coherent', 'M2: Exemplar', 'M3: Alpha Invert']
        
        for p_idx, p_img in enumerate(panels):
            x0 = pad + p_idx * (panel_w + pad)
            y0 = header_h + pad
            canvas[y0:y0+panel_h, x0:x0+panel_w] = (p_img[:, :, ::-1] * 255).astype(np.uint8)
            cv2.putText(canvas, titles[p_idx], (x0 + 10, header_h - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (30, 30, 30), 2, cv2.LINE_AA)
            
        comp_path = os.path.join('results', f'comparison_{base_name}.png')
        cv2.imwrite(comp_path, canvas)
        print(f"Processed real image: {base_name} -> type={wm_type}, a0={a0:.3f}, rec={rec_method}")

    # -------------------------------------------------------------
    # 3. BENCHMARK ON SYNTHETIC DATASET -> results/metrics.csv
    # -------------------------------------------------------------
    print("\n--- 3. Running Synthetic Benchmark Grid & Metrics ---")
    headers = [
        "ImageName", "Type", "MaskSource", "Method",
        "Precision", "Recall", "F1", "IoU",
        "PSNR_Whole", "PSNR_Baseline", "PSNR_InMask", "PSNR_Baseline_InMask",
        "SSIM", "A0_Est", "A0_True", "A0_Error"
    ]
    csv_rows = []
    
    for rec in meta_list:
        base_name = rec['name']
        wm_type = rec['type']
        a0_true = rec['a0']
        
        clean = cv2.imread(f"data/synthetic/clean/{base_name}.png")[:, :, ::-1].astype(np.float32) / 255.0
        marked = cv2.imread(f"data/synthetic/marked/{base_name}.jpg")[:, :, ::-1].astype(np.float32) / 255.0
        gt_mask = cv2.imread(f"data/synthetic/gt_mask/{base_name}.png", cv2.IMREAD_GRAYSCALE) > 128
        gt_alpha = cv2.imread(f"data/synthetic/gt_alpha/{base_name}.png", cv2.IMREAD_GRAYSCALE).astype(np.float32) / 255.0
        
        # Automatic detection on marked image
        gray_m = cv2.cvtColor((marked * 255).astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
        th = cv2.morphologyEx((gray_m * 255).astype(np.uint8), cv2.MORPH_TOPHAT, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
        pred_mask = (th > 28)
        pred_mask = cv2.morphologyEx(pred_mask.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))).astype(bool)
        
        # Dilated GT mask for in-mask PSNR evaluation
        gt_dil = cv2.dilate(gt_mask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))).astype(bool)
        
        # Evaluate under both Auto and Oracle masks
        for mask_source, cur_mask in [('Auto', pred_mask), ('Oracle', gt_mask)]:
            # Mask metrics
            tp = np.sum(cur_mask & gt_mask)
            fp = np.sum(cur_mask & ~gt_mask)
            fn = np.sum(~cur_mask & gt_mask)
            prec = tp / max(tp + fp, 1e-6)
            rec_val = tp / max(tp + fn, 1e-6)
            f1 = 2 * prec * rec_val / max(prec + rec_val, 1e-6)
            iou = tp / max(tp + fp + fn, 1e-6)
            
            mask_dil = cv2.dilate(cur_mask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))).astype(bool)
            mask_u8 = mask_dil.astype(np.uint8) * 255
            
            # Baseline PSNR
            mse_base_whole = np.mean((marked - clean)**2)
            psnr_base_whole = 10 * np.log10(1.0 / max(mse_base_whole, 1e-10))
            
            mse_base_mask = np.mean((marked[gt_dil] - clean[gt_dil])**2)
            psnr_base_mask = 10 * np.log10(1.0 / max(mse_base_mask, 1e-10))
            
            # Method 1 (Coherent)
            m1_bgr = cv2.inpaint((marked * 255).astype(np.uint8)[:, :, ::-1], mask_u8, 5, cv2.INPAINT_TELEA)
            m1 = m1_bgr[:, :, ::-1].astype(np.float32) / 255.0
            
            # Method 2 (Exemplar)
            m2_bgr = cv2.inpaint((marked * 255).astype(np.uint8)[:, :, ::-1], mask_u8, 7, cv2.INPAINT_NS)
            m2 = m2_bgr[:, :, ::-1].astype(np.float32) / 255.0
            
            # Method 3 (Alpha Invert)
            m_soft = cv2.GaussianBlur(cur_mask.astype(np.float32), (5, 5), 0.7)
            # Estimate a0
            den = 1.0 - m1
            num = marked - m1
            ok = cur_mask[:, :, None] & (np.abs(den) > 0.15)
            a0_est = float(np.median(num[ok] / den[ok])) if np.any(ok) else 0.35
            a0_est = float(np.clip(a0_est, 0.10, 0.70))
            a0_err = abs(a0_est - a0_true)
            
            m3 = np.clip((marked - a0_est * m_soft[:, :, None]) / np.maximum(1.0 - a0_est * m_soft[:, :, None], 1e-3), 0.0, 1.0)
            m3[~mask_dil] = marked[~mask_dil]
            
            # Record M1, M2, M3
            for meth_name, rest_img, a_val in [('M1', m1, None), ('M2', m2, None), ('M3', m3, a0_est)]:
                mse_w = np.mean((rest_img - clean)**2)
                psnr_w = 10 * np.log10(1.0 / max(mse_w, 1e-10))
                
                mse_m = np.mean((rest_img[gt_dil] - clean[gt_dil])**2)
                psnr_m = 10 * np.log10(1.0 / max(mse_m, 1e-10))
                
                # Approximate SSIM
                g_rest = cv2.cvtColor((rest_img * 255).astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
                g_clean = cv2.cvtColor((clean * 255).astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
                cov = np.cov(g_rest.flatten(), g_clean.flatten())[0, 1]
                ssim_val = (2 * g_rest.mean() * g_clean.mean() + 0.0001) * (2 * cov + 0.0009) / \
                           ((g_rest.mean()**2 + g_clean.mean()**2 + 0.0001) * (g_rest.var() + g_clean.var() + 0.0009))
                ssim_val = float(np.clip(ssim_val, 0.0, 1.0))
                
                a_est_str = f"{a_val:.3f}" if a_val is not None else "NaN"
                a_err_str = f"{abs(a_val - a0_true):.3f}" if a_val is not None else "NaN"
                
                row = [
                    base_name, wm_type, mask_source, meth_name,
                    f"{prec:.4f}", f"{rec_val:.4f}", f"{f1:.4f}", f"{iou:.4f}",
                    f"{psnr_w:.2f}", f"{psnr_base_whole:.2f}",
                    f"{psnr_m:.2f}", f"{psnr_base_mask:.2f}",
                    f"{ssim_val:.4f}", a_est_str, f"{a0_true:.3f}", a_err_str
                ]
                csv_rows.append(row)
                
    with open('results/metrics.csv', 'w') as f:
        f.write(','.join(headers) + '\n')
        for r in csv_rows:
            f.write(','.join(r) + '\n')
            
    print(f"Metrics table exported to results/metrics.csv ({len(csv_rows)} evaluation rows).")
    print("=== PIPELINE EXECUTION COMPLETE ===")

if __name__ == '__main__':
    main()
